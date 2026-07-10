class BeneficiarySerializer
  include JSONAPI::Serializer

  attributes :id, :user_id, :name, :last_name, :email, :phone,
             :address1, :address2, :zip_code, :state, :city,
             :created_at, :updated_at
end

