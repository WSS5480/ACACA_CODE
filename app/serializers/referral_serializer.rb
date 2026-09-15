class ReferralSerializer
  include JSONAPI::Serializer

  attributes :id, :order_id, :nationality, :country, :name, :last_name, :phone, :phone_work,
             :created_at, :updated_at
end

