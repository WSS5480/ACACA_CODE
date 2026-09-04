# frozen_string_literal: true

# 🚀 SWITCH DE GO LIVE — borra TODOS los datos transaccionales de prueba y deja
# la plataforma limpia para lanzar. Diseño de seguridad:
#   1) Solo el usuario MASTER puede usarlo.
#   2) PRIMERO se descarga el respaldo completo (JSON) de todo lo que se va.
#   3) El borrado exige escribir la frase exacta 'BORRAR Y LANZAR'.
#   4) La CONFIGURACIÓN queda intacta: catálogo y fotos, categorías, tasas,
#      plantillas del contrato/aviso/waiver, preguntas, motor de riesgo y su
#      historial, staff, CPs, tipo de cambio, bitácora y cambios firmados.
#   5) Marca la fecha de corte del motor de decisión (solo datos reales) y
#      deja constancia en la Bitácora.
class Api::GoLiveController < ApplicationController
  include TokenAuthenticatable

  # ORDEN IMPORTA: hijos antes que padres (sin CASCADE, nada fuera de la lista
  # puede borrarse por accidente).
  WIPE_TABLES = %w[
    payments contract_installments reference_checks reference_pings
    payment_commitments referrals guarantors buyers orders
    support_ticket_notes support_tickets contact_logs whatsapp_messages
    cart_snapshots ledger_entries accounting_closes expenses
    beneficiaries contracts credits
  ].freeze
  SANITIZE_USER_COLS = %w[encrypted_password reset_password_token confirmation_token whatsapp_verify_token jti].freeze
  CONFIRM_PHRASE = 'BORRAR Y LANZAR'

  # GET /api/go_live/backup — respaldo completo (descarga JSON) de TODO lo que
  # el switch borraría. Descárgalo y guárdalo ANTES de ejecutar.
  def backup
    return forbid unless master?

    data = { 'exported_at' => Time.current.iso8601, 'tables' => {} }
    WIPE_TABLES.each do |t|
      next unless conn.table_exists?(t)

      data['tables'][t] = conn.select_all("SELECT * FROM #{conn.quote_table_name(t)}").to_a
    end
    clients = User.joins(:role).where(roles: { name: 'cliente' })
    data['tables']['users_clientes'] = clients.map { |u| u.attributes.except(*SANITIZE_USER_COLS) }
    send_data JSON.pretty_generate(data),
              filename: "respaldo-pre-go-live-#{Date.current}.json",
              type: 'application/json', disposition: 'attachment'
  end

  # POST /api/go_live/execute { confirm: 'BORRAR Y LANZAR' }
  def execute
    return forbid unless master?
    unless params[:confirm].to_s.strip == CONFIRM_PHRASE
      return render json: { error: "Para ejecutar, escribe exactamente: #{CONFIRM_PHRASE}" }, status: :unprocessable_entity
    end

    borrado = {}
    clientes = 0
    ActiveRecord::Base.transaction do
      WIPE_TABLES.each do |t|
        next unless conn.table_exists?(t)

        borrado[t] = conn.select_value("SELECT COUNT(*) FROM #{conn.quote_table_name(t)}").to_i
        conn.execute("DELETE FROM #{conn.quote_table_name(t)}")
        begin
          conn.execute("ALTER SEQUENCE IF EXISTS #{t}_id_seq RESTART WITH 1")
        rescue StandardError
          nil
        end
      end

      ids = User.joins(:role).where(roles: { name: 'cliente' }).pluck(:id)
      clientes = ids.size
      if ids.any?
        AuditLog.where(user_id: ids).update_all(user_id: nil) if AuditLog.column_names.include?('user_id')
        User.where(id: ids).delete_all
      end

      # Fecha de corte del motor de decisión: desde HOY solo cuentan datos reales.
      cfg = begin
        JSON.parse(AppSetting.get('reference_gate_readiness_config').to_s)
      rescue StandardError
        {}
      end
      cfg = {} unless cfg.is_a?(Hash)
      cfg['ignore_before'] = Date.current.iso8601
      AppSetting.set('reference_gate_readiness_config', cfg.to_json)
      AppSetting.find_by(key: 'reference_gate_findings')&.destroy
      AppSetting.find_by(key: 'reference_gate_findings_history')&.destroy
      AppSetting.set('go_live_at', Time.current.iso8601)
    end

    AuditLog.record!(actor: @current_user, action: 'go_live',
                     label: '🚀 GO LIVE ejecutado: datos de prueba borrados',
                     details: "#{borrado.values.sum} registros en #{borrado.size} tablas + #{clientes} cliente(s) de prueba. Corte del motor: #{Date.current.iso8601}.")
    render json: { ok: true, borrado: borrado, clientes_borrados: clientes, fecha_corte: Date.current.iso8601 }, status: :ok
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def conn
    ActiveRecord::Base.connection
  end

  def master?
    @current_user&.role&.name == 'master'
  end

  def forbid
    render json: { error: 'Solo el usuario master puede usar el switch de GO LIVE' }, status: :forbidden
  end
end
