class ContractSerializer
  include JSONAPI::Serializer

  attributes :id, :user_id, :contract_number, :status, :total_amount, :downpayment,
             :financed_amount, :weekly_payment, :weeks, :start_date, :created_at

  attribute :client_name do |c|
    [c.user&.name, c.user&.last_name].compact.join(' ').strip
  end
  attribute :client_number do |c|
    c.user&.number
  end
  attribute :balance do |c|
    c.balance
  end
  attribute :total_paid do |c|
    c.total_paid
  end
  attribute :payment_status do |c|
    c.payment_status
  end
  attribute :items_count do |c|
    c.orders.size
  end
  attribute :past_due_amount do |c|
    c.past_due_amount
  end
  attribute :next_due_date do |c|
    c.next_due_date
  end
  attribute :days_past_due do |c|
    c.days_past_due
  end
  attribute :frequency do |c|
    c.freq
  end
  attribute :first_due_date do |c|
    c.first_due_date
  end
  attribute :initial_payment do |c|
    c.initial_payment
  end
  attribute :waiver do |c|
    c.orders.first&.waiver
  end
  attribute :first_order_id do |c|
    c.orders.first&.id
  end
end
