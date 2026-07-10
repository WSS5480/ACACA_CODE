class UserSerializer
  include JSONAPI::Serializer
  attributes :id, :email, :name, :last_name, :number, :phone, :housing_type, :months_usa, :months_address, :months_job, :estimated_income, :delivery_country, :shared_income, :role_id, :credit_amount

  attribute :role do |user|
    if user.role.present?
      { name: user.role.name, label: user.role.label }
    end
  end

  # Versión del motor de riesgo con la que se evaluó al cliente (protegido por si aún no existe la columna).
  attribute :risk_version do |user|
    user.has_attribute?(:risk_version) ? user.risk_version : nil
  end
end
