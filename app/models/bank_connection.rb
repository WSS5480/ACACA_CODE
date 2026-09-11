# frozen_string_literal: true

# CONEXIÓN con un banco (un "Item" de Plaid, o una cuenta manual alimentada
# con estados de cuenta). El token de acceso del proveedor se guarda CIFRADO con
# una llave derivada de SECRET_KEY_BASE: un volcado de la base de datos no sirve
# para leer las cuentas. Nunca se expone por la API.
class BankConnection < ApplicationRecord
  PROVIDERS = %w[plaid manual].freeze
  STATUSES  = %w[active login_required error disconnected].freeze

  has_many :bank_accounts, dependent: :restrict_with_exception
  has_many :bank_transactions, through: :bank_accounts

  validates :provider, inclusion: { in: PROVIDERS }
  validates :external_id, presence: true, uniqueness: { scope: :provider }
  validates :status, inclusion: { in: STATUSES }

  scope :live,      -> { where.not(status: 'disconnected') }
  scope :automatic, -> { live.where(provider: 'plaid') }

  def self.encryptor
    key = Rails.application.key_generator.generate_key('bank_connections/access_token', ActiveSupport::MessageEncryptor.key_len)
    ActiveSupport::MessageEncryptor.new(key)
  end

  def access_token=(value)
    self.access_token_enc = value.present? ? self.class.encryptor.encrypt_and_sign(value.to_s) : nil
  end

  def access_token
    return nil if access_token_enc.blank?

    self.class.encryptor.decrypt_and_verify(access_token_enc)
  rescue ActiveSupport::MessageEncryptor::InvalidMessage, ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end

  def manual?  = provider == 'manual'
  def plaid?   = provider == 'plaid'
  def active?  = status == 'active'

  def label
    institution_name.presence || (manual? ? 'Cuenta manual' : provider.titleize)
  end

  # El webhook del proveedor solo deja una marca; el tick de 15 min sincroniza.
  def request_sync!
    update_columns(sync_requested_at: Time.current, last_webhook_at: Time.current)
  end

  def due_for_sync?(full: false)
    return false unless plaid? && %w[active error].include?(status)
    return true if full || sync_requested_at.present? || last_synced_at.nil?

    last_synced_at < 20.hours.ago
  end

  def mark_error!(message, login_required: false)
    update_columns(status: (login_required ? 'login_required' : 'error'), last_error: message.to_s.truncate(500), updated_at: Time.current)
  end

  def as_json_admin
    { id: id, provider: provider, institution_id: institution_id, institution_name: label, country: country,
      status: status, last_synced_at: last_synced_at, last_error: last_error, sync_requested_at: sync_requested_at,
      created_at: created_at, disconnected_at: disconnected_at,
      accounts: bank_accounts.order(:id).map(&:as_json_admin) }
  end
end
