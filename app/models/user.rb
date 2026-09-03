class User < ApplicationRecord
  include Devise::JWT::RevocationStrategies::JTIMatcher
  include CreditCalculable

  # Include default devise modules. Others available are:
  # :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :validatable,
         :confirmable,
         :jwt_authenticatable,
         jwt_revocation_strategy: self

  belongs_to :role
  has_one :credit, dependent: :destroy
  has_many :orders, dependent: :nullify
  has_many :contracts, dependent: :nullify
  has_many :payments, dependent: :nullify
  has_many :beneficiaries, dependent: :destroy

  # Parentesco REAL para el motor de riesgo: el del PRIMER "quien recibe" del
  # cliente (su destinatario principal). nil mientras no haya ninguno — en ese
  # caso el motor usa su valor por defecto, como en el registro.
  def primary_kinship
    b = beneficiaries.order(:created_at).first
    b && b.respond_to?(:kinship) ? b.kinship.presence : nil
  end

  # Recalcula la línea con el motor ACTIVO y el parentesco real, respetando lo
  # ya usado: nueva disponible = nuevo límite - usado (nunca negativa).
  def recalculate_credit!
    new_limit = calculate_initial_credit(relationship: primary_kinship).to_f.round(2)
    cr = credit || build_credit(amount: new_limit)
    has_limit = Credit.column_names.include?('credit_limit')
    old_limit = has_limit && cr.credit_limit ? cr.credit_limit.to_f : cr.amount.to_f
    used = [(old_limit - cr.amount.to_f), 0].max
    cr.amount = [(new_limit - used), 0].max.round(2)
    cr.credit_limit = new_limit if has_limit
    cr.save!
    update_column(:risk_version, risk_engine_version) if User.column_names.include?('risk_version')
    cr
  end

  validates :housing_type, inclusion: { in: %w[owner tenant], message: 'debe ser owner o tenant' }, allow_nil: true

  # No usamos el correo de confirmación por defecto de Devise: los clientes reciben el link en el correo de
  # bienvenida, y los no-clientes se confirman al crearse (API y seeds).
  def send_confirmation_instructions
    true
  end

  # --- Verificacion por WhatsApp ---
  def ensure_whatsapp_verify_token!
    return whatsapp_verify_token if whatsapp_verify_token.present?
    token = nil
    loop do
      token = SecureRandom.alphanumeric(10)
      break unless User.exists?(whatsapp_verify_token: token)
    end
    update_column(:whatsapp_verify_token, token)
    token
  end

  # --- Credito disponible en base a contratos ---
  def credit_limit
    (credit&.respond_to?(:credit_limit) ? credit.credit_limit : nil) || credit&.amount || 0
  end

  def outstanding_balance
    contracts.where(status: 'active').to_a.sum { |c| c.balance }.round(2)
  rescue StandardError
    0
  end

  def available_credit
    (credit&.amount || 0).to_f.round(2)
  end

  def whatsapp_verify_url
    # Número de la empresa: de ENV, o se consulta a Meta una vez y se cachea.
    num = ENV['WHATSAPP_BUSINESS_NUMBER'].to_s.gsub(/[^0-9]/, '')
    num = User.business_whatsapp_digits if num.blank?
    return nil if num.blank?
    token = has_attribute?(:whatsapp_verify_token) ? whatsapp_verify_token : nil
    return nil if token.blank?
    text = "Hola, quiero verificar mi cuenta acasa. Codigo: #{token}"
    "https://wa.me/#{num}?text=#{ERB::Util.url_encode(text)}"
  rescue StandardError
    nil
  end

  # Dígitos del número de WhatsApp de la empresa (para enlaces wa.me), leídos
  # de Meta y cacheados 12 h. Respaldo cuando WHATSAPP_BUSINESS_NUMBER no está.
  # DUEÑO de un número de WhatsApp: SIEMPRE la cuenta VERIFICADA por WhatsApp
  # (la más antigua si hubiera duplicados); si ninguna está verificada, la más
  # antigua. Toda conversación se liga al cliente con su número verificado.
  def self.by_whatsapp_tail(raw)
    t = raw.to_s.gsub(/\D/, '')[-10..]
    return nil if t.blank? || t.length < 10

    scope = where("regexp_replace(coalesce(phone,''), '[^0-9]', '', 'g') LIKE ?", "%#{t}")
    scope.where.not(confirmed_at: nil).order(:created_at).first || scope.order(:created_at).first
  end

  def self.business_whatsapp_digits
    Rails.cache.fetch('wa_business_digits', expires_in: 12.hours) do
      WhatsappCloud.configured? ? WhatsappCloud.new.display_number_digits : nil
    end
  rescue StandardError
    nil
  end

  def send_reset_password_instructions
    # Generate token using Devise's method
    raw_token, encrypted_token = Devise.token_generator.generate(self.class, :reset_password_token)
    
    # Set token and sent_at
    self.reset_password_token = encrypted_token
    self.reset_password_sent_at = Time.current
    
    # Save without validations to avoid issues
    if save(validate: false)
      # In development, send email synchronously for easier testing
      # In production, queue the email job asynchronously
      if Rails.env.development?
        Rails.logger.info "📧 Sending password reset email synchronously (development mode)"
        DeviseMailer.reset_password_instructions(self, raw_token).deliver_now
      else
        Rails.logger.info "📧 Queueing password reset email job (production mode)"
        Mailing::PasswordResetMailerJob.perform_async(id, raw_token)
      end
      true
    else
      false
    end
  end

  def credit_amount
    credit&.amount || 0
  end
end
