# frozen_string_literal: true

require 'digest'

# BANCOS — espacio de nombres de la integración bancaria (ver app/services/bank_feeds/*).
module BankFeeds
  # Token secreto que va en la URL de los webhooks (…/api/bank/webhooks/plaid/<token>).
  # Se deriva de SECRET_KEY_BASE: estable entre arranques y sin variable extra.
  # El webhook SOLO marca una conexión para sincronizar; nunca se confía en su contenido.
  def self.webhook_token
    Digest::SHA256.hexdigest(Rails.application.key_generator.generate_key('bank_feeds/webhook', 32))[0, 40]
  end

  # Tipo de cambio USD→MXN vigente en una fecha (el más reciente registrado hasta ese día).
  def self.usd_to_mxn_on(date)
    return nil unless defined?(ExchangeRate) && ExchangeRate.table_exists?

    r = ExchangeRate.where('created_at <= ?', date.to_date.end_of_day).order(created_at: :desc).limit(1).pick(:usd_to_mxn)
    r ||= ExchangeRate.order(created_at: :desc).limit(1).pick(:usd_to_mxn)
    r&.to_f&.positive? ? r.to_f : nil
  end
end
