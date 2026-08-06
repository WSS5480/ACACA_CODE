# frozen_string_literal: true

module Api
  # Carritos abandonados (CRM). El storefront reporta el carrito de los
  # clientes con sesión iniciada; el admin los ve en el CRM para darles
  # seguimiento por WhatsApp antes de que se enfríen.
  class CartsController < ApplicationController
    include ClientOrTokenAuthenticatable

    skip_before_action :authenticate_client_or_user!, raise: false
    before_action :authenticate_client_or_user!

    # POST /api/carts/track { items: [{product_id, title, total_price}], total }
    # Cliente: guarda/actualiza la foto de SU carrito. Vacío = se borra.
    def track
      return render(json: { ok: true, skipped: true }, status: :ok) unless snapshots_ready?
      user = acting_as_client? ? @current_user : nil
      return render(json: { error: 'Solo clientes' }, status: :forbidden) unless user

      items = Array(params[:items]).map do |i|
        { 'product_id' => i[:product_id] || i['product_id'],
          'title' => (i[:title] || i['title']).to_s[0, 200],
          'total_price' => (i[:total_price] || i['total_price']).to_f.round(2) }
      end

      if items.empty?
        CartSnapshot.where(user_id: user.id).delete_all
        return render json: { ok: true, cleared: true }, status: :ok
      end

      snap = CartSnapshot.find_or_initialize_by(user_id: user.id)
      snap.items = items.to_json
      snap.total = items.sum { |i| i['total_price'].to_f }.round(2)
      snap.save!
      render json: { ok: true }, status: :ok
    rescue StandardError => e
      Rails.logger.warn "[carts] no se pudo guardar el carrito: #{e.message}"
      render json: { ok: false }, status: :ok
    end

    # GET /api/carts  (staff) -> carritos abandonados para el CRM
    def index
      return render(json: { error: 'No autorizado' }, status: :forbidden) unless staff_view?
      return render(json: { carts: [] }, status: :ok) unless snapshots_ready?

      snaps = CartSnapshot.includes(:user).order(updated_at: :desc).limit(300)
      render json: {
        carts: snaps.map do |s|
          u = s.user
          { user_id: s.user_id,
            name: [u&.name, u&.last_name].compact.join(' ').strip.presence || u&.email,
            email: u&.email, phone: u&.phone,
            items: s.items_list, total: s.total.to_f,
            updated_at: s.updated_at }
        end
      }, status: :ok
    end

    # DELETE /api/carts/:user_id  (staff) -> descartar del CRM
    def destroy
      return render(json: { error: 'No autorizado' }, status: :forbidden) unless staff_view?
      return render(json: { ok: true }, status: :ok) unless snapshots_ready?

      CartSnapshot.where(user_id: params[:id]).delete_all
      render json: { ok: true }, status: :ok
    end

    private

    def staff_view?
      role = @current_user.respond_to?(:role) ? @current_user&.role&.name : nil
      %w[master admin sistema editor operador gerente admin_cuentas admin_redes].include?(role)
    end

    def snapshots_ready?
      CartSnapshot.table_exists?
    rescue StandardError
      false
    end
  end
end
