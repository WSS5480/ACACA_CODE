# frozen_string_literal: true

# COMPRADORES EN CUALQUIER PAÍS (la entrega sigue siendo en México).
#   * users.country_of_residence (ISO-3166 alfa-2) y users.timezone: hasta hoy se
#     asumía EE. UU.; months_usa pasa a significar "meses en el país donde vive".
#   * buyers.living_country: el domicilio del comprador deja de ser un ZIP de EE. UU.
#   * referrals.country: las 2 referencias "de allá" son del país donde vive el
#     comprador (el valor interno 'american' se conserva por compatibilidad).
#   * Cuentas EXISTENTES: se infiere el país por la lada del teléfono (10 dígitos
#     sin lada = EE. UU., convención histórica de la tienda); nada se borra.
#   * Semilla de preguntas de aprobación: si siguen con el texto original, se
#     actualiza la redacción "Estados Unidos" → "el país donde vives".
#   * Ajuste inicial de países atendidos (todos menos los sancionados de forma integral).
class GoGlobal < ActiveRecord::Migration[7.1]
  OLD_TO_NEW = {
    '¿Cuántos meses llevas viviendo en Estados Unidos?' => '¿Cuántos meses llevas viviendo en el país donde vives?',
    'Domicilio completo en EE.UU. y tipo de vivienda (propia o rentada)' => 'Domicilio completo en el país donde vives y tipo de vivienda (propia o rentada)',
    '2 referencias en Estados Unidos (nombre, teléfono y tel. de trabajo)' => '2 referencias en el país donde vives (nombre, teléfono y tel. de trabajo)'
  }.freeze

  def up
    add_column :users, :country_of_residence, :string, limit: 2 unless column_exists?(:users, :country_of_residence)
    add_column :users, :timezone, :string unless column_exists?(:users, :timezone)
    add_index  :users, :country_of_residence unless index_exists?(:users, :country_of_residence)
    add_column :buyers, :living_country, :string, limit: 2 unless column_exists?(:buyers, :living_country)
    add_column :referrals, :country, :string, limit: 2 unless column_exists?(:referrals, :country)

    backfill_countries!
    reword_questions!
    seed_serving_countries!
  end

  def down
    remove_column :referrals, :country if column_exists?(:referrals, :country)
    remove_column :buyers, :living_country if column_exists?(:buyers, :living_country)
    remove_index  :users, :country_of_residence if index_exists?(:users, :country_of_residence)
    remove_column :users, :timezone if column_exists?(:users, :timezone)
    remove_column :users, :country_of_residence if column_exists?(:users, :country_of_residence)
  end

  private

  # País por la lada del teléfono (PhoneGeo); compradores existentes vivían en EE. UU.
  def backfill_countries!
    return unless defined?(PhoneGeo)

    say_with_time 'País de residencia de cuentas existentes (por la lada del teléfono)' do
      n = 0
      execute("SELECT id, phone FROM users WHERE country_of_residence IS NULL AND phone IS NOT NULL AND phone <> ''").each do |row|
        iso = PhoneGeo.country_of(row['phone'])
        next if iso.blank?

        execute("UPDATE users SET country_of_residence = #{quote(iso)}, timezone = #{quote(PhoneGeo.timezone_for_country(iso))} WHERE id = #{row['id'].to_i}")
        n += 1
      end
      n
    end
    say_with_time 'Compradores existentes con domicilio → EE. UU.; referencias por nacionalidad' do
      execute("UPDATE buyers SET living_country = 'US' WHERE living_country IS NULL AND (living_zip_code IS NOT NULL AND living_zip_code <> '')")
      execute("UPDATE referrals SET country = 'MX' WHERE country IS NULL AND nationality = 'mexican'")
      execute("UPDATE referrals SET country = 'US' WHERE country IS NULL AND nationality = 'american'")
      nil
    end
  end

  def reword_questions!
    row = execute("SELECT id, value FROM app_settings WHERE key = 'approval_questions' LIMIT 1").first
    return unless row && row['value'].present?

    data = JSON.parse(row['value'])
    return unless data.is_a?(Hash)

    changed = false
    %w[pre final].each do |k|
      Array(data[k]).each do |q|
        next unless q.is_a?(Hash) && OLD_TO_NEW.key?(q['text'].to_s.strip)

        q['text'] = OLD_TO_NEW[q['text'].to_s.strip]
        changed = true
      end
    end
    return unless changed

    execute("UPDATE app_settings SET value = #{quote(JSON.generate(data))}, updated_at = NOW() WHERE id = #{row['id'].to_i}")
    say 'Preguntas de aprobación: redacción actualizada (país donde vives)'
  rescue JSON::ParserError
    nil
  end

  def seed_serving_countries!
    exists = execute("SELECT 1 FROM app_settings WHERE key = 'serving_countries' LIMIT 1").first
    return if exists

    blocked = defined?(PhoneGeo) ? PhoneGeo::DEFAULT_BLOCKED : %w[CU IR KP]
    value = JSON.generate('allowed' => [], 'blocked' => blocked, 'caps' => {})
    execute("INSERT INTO app_settings (key, value, created_at, updated_at) VALUES ('serving_countries', #{quote(value)}, NOW(), NOW())")
  end
end
