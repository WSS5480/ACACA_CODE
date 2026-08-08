class UserSerializer
  # Aviso de teléfono mal capturado (WhatsApp nunca entregaría ahí)
  def self.phone_problem(u)
    defined?(PhoneCheck) ? PhoneCheck.problem(u.phone) : nil
  rescue StandardError
    nil
  end

  include JSONAPI::Serializer
  attributes :id, :email, :name, :last_name, :number, :phone, :housing_type, :months_usa, :months_address, :months_job, :estimated_income, :delivery_country, :shared_income, :role_id, :credit_amount

  # Si el teléfono está mal capturado, aquí viene el motivo (nil = correcto)
  attribute :phone_problem do |user|
    UserSerializer.phone_problem(user)
  end

  attribute :credit_limit do |user|
    user.credit_limit
  end

  attribute :account_balance do |user|
    user.outstanding_balance
  end

  attribute :role do |user|
    if user.role.present?
      { name: user.role.name, label: user.role.label }
    end
  end

  # Estado de la CUENTA del cliente (columna en Clientes):
  # active (debe y está pagando) · paid_off (liquidado) · returned (devuelto)
  # · charged_off (castigado) · nil (sin contratos con pago inicial).
  # Prioridad: castigado > activo > devuelto > liquidado.
  attribute :account_state do |user|
    begin
      cs = user.respond_to?(:contracts) ? user.contracts.to_a : []
      if cs.empty?
        nil
      elsif cs.any? { |c| c.status == 'charged_off' }
        'charged_off'
      else
        paid = Payment.where(contract_id: cs.map(&:id)).group(:contract_id).sum(:amount)
        open_active = cs.any? do |c|
          c.status == 'active' && paid[c.id].to_f.positive? &&
            (c.financed_amount.to_f - paid[c.id].to_f) > 0.009
        end
        settled = cs.any? do |c|
          c.status == 'paid' ||
            (c.status == 'active' && paid[c.id].to_f.positive? && (c.financed_amount.to_f - paid[c.id].to_f) <= 0.009)
        end
        if open_active then 'active'
        elsif cs.any? { |c| c.status == 'returned' } then 'returned'
        elsif settled then 'paid_off'
        end
      end
    rescue StandardError
      nil
    end
  end

  # Versión del motor de riesgo con la que se evaluó al cliente (protegido por si aún no existe la columna).
  # Estado de verificacion (confirmacion por WhatsApp). El front decide si pide el codigo.
  attribute :confirmed do |user|
    user.confirmed?
  end

  # Enlace wa.me con el token para que el cliente nos escriba y active su cuenta.
  attribute :whatsapp_verify_url do |user|
    user.whatsapp_verify_url
  end

  attribute :risk_version do |user|
    user.has_attribute?(:risk_version) ? user.risk_version : nil
  end
end
