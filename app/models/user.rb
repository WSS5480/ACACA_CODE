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
  has_many :beneficiaries, dependent: :destroy

  validates :housing_type, inclusion: { in: %w[owner tenant], message: 'debe ser owner o tenant' }, allow_nil: true

  # No usamos el correo de confirmación por defecto de Devise: los clientes reciben el link en el correo de
  # bienvenida, y los no-clientes se confirman al crearse (API y seeds).
  def send_confirmation_instructions
    true
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
