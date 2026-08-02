class ContractInstallmentSerializer
  include JSONAPI::Serializer
  attributes :id, :number, :due_date, :amount, :paid_amount, :status, :paid_at
end
