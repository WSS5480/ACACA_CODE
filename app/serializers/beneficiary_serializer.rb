class BeneficiarySerializer
  include JSONAPI::Serializer

  attributes :id, :user_id, :name, :last_name, :email, :phone,
             :address1, :address2, :zip_code, :state, :city,
             :created_at, :updated_at

  # Defensivo: si la migración de kinship aún no corre, responder nil en lugar
  # de tirar 500 (rompía la lista de quien recibe en el carrito).
  attribute :kinship do |b|
    b.respond_to?(:kinship) ? b.kinship : nil
  end
end

