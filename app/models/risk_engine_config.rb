class RiskEngineConfig < ApplicationRecord
  # Cada registro es una VERSIÓN del motor de riesgo. Sólo una está activa.
  # `config` guarda las tablas de puntaje (mismo formato que CreditCalculable::DEFAULTS).
  # `notes` guarda el motivo del cambio (para recordar por qué se hizo).

  validates :version, presence: true, uniqueness: true

  before_save :deactivate_others, if: :active?

  def self.active_record
    where(active: true).order(version: :desc).first
  end

  def self.active_config
    active_record&.config
  end

  def self.active_version
    active_record&.version || CreditCalculable::DEFAULT_VERSION
  end

  def self.next_version
    (maximum(:version) || CreditCalculable::DEFAULT_VERSION) + 1
  end

  private

  def deactivate_others
    RiskEngineConfig.where.not(id: id).update_all(active: false)
  end
end
