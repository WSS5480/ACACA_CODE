# frozen_string_literal: true

module Api
  # CRM — CUENTAS NUEVAS SIN COMPRA: clientes que se registraron (con o sin
  # verificar por WhatsApp) y nunca regresaron: sin pedido y sin carrito.
  # Igual que los carritos abandonados: contactar, y LIBERAR si no hay manera
  # de localizarlos (la cuenta no se borra; solo sale del seguimiento).
  class LeadsController < ApplicationController
    include TokenAuthenticatable

    ROLES = %w[master admin sistema editor operador gerente admin_cuentas admin_redes].freeze
    before_action :authorize_staff!

    # GET /api/crm/leads
    def index
      cliente_role = Role.find_by(name: 'cliente')
      return render(json: { leads: [] }, status: :ok) unless cliente_role

      scope = User.where(role_id: cliente_role.id)
      scope = scope.where(crm_dismissed_at: nil) if User.column_names.include?('crm_dismissed_at')
      # Sin compra: ni contrato/pedido, ni carrito activo (esos ya salen en sus listas).
      with_contract = Contract.select(:user_id)
      scope = scope.where.not(id: with_contract)
      scope = scope.where.not(id: CartSnapshot.select(:user_id)) if defined?(CartSnapshot) && CartSnapshot.table_exists?

      rows = scope.order(created_at: :desc).limit(300).to_a
      # ⚠ Duplicados: mismo teléfono que una cuenta VERIFICADA más antigua.
      tails = rows.map { |u| u.phone.to_s.gsub(/\D/, '')[-10..] }.compact.uniq.reject { |t| t.length < 10 }
      dup_map = {}
      if tails.any?
        User.where.not(confirmed_at: nil)
            .where("regexp_replace(coalesce(phone,''), '[^0-9]', '', 'g') ~ ?", "(#{tails.join('|')})$")
            .order(:created_at).each do |e|
          t = e.phone.to_s.gsub(/\D/, '')[-10..]
          dup_map[t] ||= e
        end
      end
      leads = rows.map do |u|
        t = u.phone.to_s.gsub(/\D/, '')[-10..]
        dup = t && dup_map[t]
        dup = nil if dup && dup.id == u.id
        { id: u.id, name: [u.name, u.last_name].compact.join(' ').strip.presence || u.email,
          email: u.email, phone: u.phone,
          confirmed: u.respond_to?(:confirmed?) ? u.confirmed? : true,
          phone_problem: (PhoneCheck.problem(u.phone) rescue nil),
          duplicate_of: (dup ? "##{dup.number} · #{[dup.name, dup.last_name].compact.join(' ').strip.presence || dup.email}" : nil),
          created_at: u.created_at }
      end
      render json: { leads: leads }, status: :ok
    end

    # POST /api/crm/leads/:id/dismiss  -> LIBERAR del CRM (no borra la cuenta)
    def dismiss
      u = User.find(params[:id])
      unless User.column_names.include?('crm_dismissed_at')
        return render(json: { error: 'Falta la migración (crm_dismissed_at)' }, status: :unprocessable_entity)
      end

      u.update_column(:crm_dismissed_at, Time.current)
      AuditLog.record!(actor: @current_user, action: 'lead_released', target: u,
                       label: [u.name, u.last_name].compact.join(' ').strip.presence || u.email,
                       details: 'Liberado del CRM (cuenta nueva sin compra, sin contacto)')
      render json: { ok: true }, status: :ok
    rescue ActiveRecord::RecordNotFound
      render json: { error: 'Cliente no encontrado' }, status: :not_found
    end

    private

    def authorize_staff!
      return if ROLES.include?(@current_user&.role&.name)

      render json: { error: 'No autorizado' }, status: :forbidden
    end
  end
end
