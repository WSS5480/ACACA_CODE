# frozen_string_literal: true

# MOVIMIENTO bancario. amount CON SIGNO: positivo = entra dinero (depósito),
# negativo = sale (cargo). Se conserva aunque el banco lo retire (removed_at).
class BankTransaction < ApplicationRecord
  belongs_to :bank_account
  has_one :bank_connection, through: :bank_account

  validates :external_id, presence: true, uniqueness: { scope: :bank_account_id }
  validates :posted_on, presence: true
  validates :amount, presence: true

  scope :visible,  -> { where(removed_at: nil) }
  scope :inflows,  -> { where('amount > 0') }
  scope :outflows, -> { where('amount < 0') }

  def inflow?  = amount.to_f.positive?
  def outflow? = amount.to_f.negative?

  # Sugerencia de categoría de GASTO (Contabilidad) a partir de la descripción y la
  # categoría del banco. Solo prellena el formulario: la persona confirma.
  def suggested_expense_category
    d = "#{description} #{merchant_name}".downcase
    return 'comisiones'  if d =~ /stripe|bank fee|service fee|comision|comisión|wire fee|monthly fee/ || category.to_s == 'BANK_FEES'
    return 'publicidad'  if d =~ /facebook|meta ?ads|fb\.me|google ?ads|tiktok|instagram|adwords/
    return 'envio'       if d =~ /\bups\b|fedex|dhl|usps|estafeta|paquete|paquetexpress|redpack|shipping|envio|envío/
    return 'nomina'      if d =~ /payroll|nomina|nómina|gusto|adp\b|paychex/
    return 'software'    if d =~ /google|aws|amazon web services|render\.com|render inc|vercel|twilio|openai|anthropic|github|slack|zoom|microsoft|adobe|apple\.com|godaddy|namecheap|cloudflare|notion|dropbox|quickbooks|intuit/
    return 'producto'    if d =~ /amazon|amzn|mercado ?libre|walmart|costco|best ?buy|liverpool|coppel|elektra|sams/
    return 'incobrable'  if d =~ /charge.?off|castig/

    'otro'
  end

  def as_json_admin
    { id: id, account_id: bank_account_id, account_label: bank_account.label, institution_name: bank_account.bank_connection.label,
      country: bank_account.bank_connection.country, provider: bank_account.bank_connection.provider,
      posted_on: posted_on.to_s, authorized_on: authorized_on&.to_s, amount: amount.to_f, currency: currency,
      description: description, merchant_name: merchant_name, category: category, category_detail: category_detail,
      pending: pending, channel: channel, stripe_payout_id: stripe_payout_id, expense_id: expense_id,
      removed_at: removed_at, suggested_category: suggested_expense_category }
  end
end
