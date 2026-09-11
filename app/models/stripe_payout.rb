# frozen_string_literal: true

# DEPÓSITO (payout) de Stripe hacia la cuenta bancaria, copiado de la API de
# Stripe para conciliarlo contra los movimientos del banco.
class StripePayout < ApplicationRecord
  validates :stripe_id, presence: true, uniqueness: true

  scope :unmatched, -> { where(bank_transaction_id: nil) }

  def matched? = bank_transaction_id.present?

  def as_json_admin
    tx = bank_transaction_id && BankTransaction.find_by(id: bank_transaction_id)
    { id: id, stripe_id: stripe_id, amount: amount.to_f, currency: currency, arrival_on: arrival_on&.to_s, status: status,
      description: description, destination: destination, method: method, matched_at: matched_at,
      bank_transaction_id: bank_transaction_id,
      bank_transaction: tx && { id: tx.id, posted_on: tx.posted_on.to_s, amount: tx.amount.to_f, description: tx.description,
                                account_label: tx.bank_account.label, institution_name: tx.bank_account.bank_connection.label } }
  end
end
