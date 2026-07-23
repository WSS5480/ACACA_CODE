class ExchangeRateSerializer
  include JSONAPI::Serializer

  attributes :id, :usd_to_mxn, :created_at, :updated_at
end

