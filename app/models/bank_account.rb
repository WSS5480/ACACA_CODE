# frozen_string_literal: true

# CUENTA bancaria dentro de una conexión (cheques, ahorro, tarjeta de crédito…).
# Guarda el último saldo conocido; los movimientos viven en bank_transactions.
class BankAccount < ApplicationRecord
  belongs_to :bank_connection
  has_many :bank_transactions, dependent: :restrict_with_exception

  validates :external_id, presence: true, uniqueness: { scope: :bank_connection_id }

  scope :active, -> { where(active: true) }

  def label
    base = name.presence || official_name.presence || subtype.presence || 'Cuenta'
    mask.present? ? "#{base} ••••#{mask}" : base
  end

  def credit?
    kind == 'credit'
  end

  def as_json_admin
    { id: id, external_id: external_id, name: name, official_name: official_name, mask: mask, kind: kind, subtype: subtype,
      currency: currency, current_balance: current_balance&.to_f, available_balance: available_balance&.to_f,
      balance_as_of: balance_as_of, active: active, label: label,
      connection_id: bank_connection_id, provider: bank_connection.provider, country: bank_connection.country,
      institution_name: bank_connection.label, txn_count: bank_transactions.where(removed_at: nil).count,
      last_txn_on: bank_transactions.where(removed_at: nil).maximum(:posted_on) }
  end
end
