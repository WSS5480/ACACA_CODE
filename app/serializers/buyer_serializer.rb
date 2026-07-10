class BuyerSerializer
  include JSONAPI::Serializer

  attributes :id, :order_id, :name, :last_name, :nationality, :state_residence,
             :living_address1, :living_address2, :living_zip_code, :living_state,
             :living_city, :housing_type, :months_usa, :months_address, :job,
             :phone, :phone_work, :email, :weekly_income, :relationship_with_beneficiary,
             :delivery_address1, :delivery_address2, :delivery_zip_code, :delivery_state,
             :delivery_city, :phone_beneficiary, :created_at, :updated_at

  attribute :identification_url do |buyer|
    if buyer.identification.attached?
      Rails.application.routes.url_helpers.rails_blob_url(buyer.identification, only_path: false)
    end
  end

  attribute :proof_of_address_url do |buyer|
    if buyer.proof_of_address.attached?
      Rails.application.routes.url_helpers.rails_blob_url(buyer.proof_of_address, only_path: false)
    end
  end

  attribute :proof_of_income_url do |buyer|
    if buyer.proof_of_income.attached?
      Rails.application.routes.url_helpers.rails_blob_url(buyer.proof_of_income, only_path: false)
    end
  end
end

