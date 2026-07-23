module CreditCalculable
  extend ActiveSupport::Concern

  # =========================================================================
  # Motor de riesgo / crédito, con versionado.
  # Las respuestas del formulario suman PUNTOS; el total se traduce a un
  # MONTO DE CRÉDITO. La configuración vigente vive en RiskEngineConfig
  # (versión activa). Si no hay ninguna guardada, se usan estos valores por
  # defecto (equivalentes a la "Versión 2").
  # =========================================================================

  DEFAULT_VERSION = 2

  DEFAULTS = {
    'housing'         => { 'owner' => 5 },
    'months'          => [[48, 20], [24, 15], [12, 10], [6, 5]],
    'income'          => [[750, 30], [500, 25], [400, 20], [300, 15], [200, 10], [100, 5]],
    'kinship'         => { 'conyuge' => 20, 'cónyuge' => 20, 'esposo' => 20, 'esposa' => 20,
                           'hijo' => 20, 'hija' => 20, 'padre' => 20, 'madre' => 20,
                           'hermano' => 15, 'hermana' => 15, 'otro' => 10 },
    'kinship_default' => 20,
    'delivery'        => 5,
    'credit'          => [[79, 750], [69, 600], [59, 500], [49, 400], [45, 300]]
  }.freeze

  def calculate_initial_credit(relationship: nil)
    points_to_credit(calculate_client_points(relationship: relationship))
  end

  def calculate_client_points(relationship: nil)
    c = risk_config
    housing_type_points(c) +
      months_points(c, months_usa) +
      months_points(c, months_address) +
      months_points(c, months_job) +
      income_points(c) +
      kinship_points(c, relationship) +
      (c['delivery'] || 0)
  end

  # Versión del motor con la que se evaluó (para guardar en el cliente).
  def risk_engine_version
    RiskEngineConfig.active_version
  rescue StandardError
    DEFAULT_VERSION
  end

  private

  # Configuración activa (memoizada). Cae a DEFAULTS si no hay tabla/registro.
  def risk_config
    @risk_config ||= begin
      saved = (RiskEngineConfig.active_config rescue nil)
      saved.present? ? DEFAULTS.merge(saved) : DEFAULTS
    end
  end

  def housing_type_points(c)
    (c['housing'] || {})[housing_type.to_s] || 0
  end

  def months_points(c, value)
    months = value.to_i
    tier = (c['months'] || []).find { |min, _pts| months >= min }
    tier ? tier[1] : 0
  end

  def income_points(c)
    income = estimated_income.to_i
    tier = (c['income'] || []).find { |min, _pts| income >= min }
    tier ? tier[1] : 0
  end

  def kinship_points(c, relationship = nil)
    return (c['kinship_default'] || 0) if relationship.to_s.strip.empty?

    (c['kinship'] || {})[relationship.to_s.downcase.strip] || 10
  end

  def points_to_credit(points)
    tier = (risk_config['credit'] || []).find { |min, _credit| points >= min }
    tier ? tier[1] : 0
  end
end
