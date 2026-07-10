class GuarantorSerializer
  include JSONAPI::Serializer

  attributes :id, :order_id, :name, :last_name, :address1, :address2,
             :zip_code, :state, :city, :phone, :email,
             :created_at, :updated_at

  attribute :proof_of_address_url do |guarantor|
    if guarantor.proof_of_address.attached?
      Rails.application.routes.url_helpers.rails_blob_url(guarantor.proof_of_address, only_path: false)
    end
  end

  attribute :identification_url do |guarantor|
    if guarantor.identification.attached?
      Rails.application.routes.url_helpers.rails_blob_url(guarantor.identification, only_path: false)
    end
  end
end

