class ZipCodeSerializer
  include JSONAPI::Serializer

  attributes :id, :code, :country, :state_initials, :state_name, :city, :municipality, :settlement, :created_at, :updated_at
end
