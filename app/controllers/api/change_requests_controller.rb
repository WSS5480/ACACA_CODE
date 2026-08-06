# frozen_string_literal: true

module Api
  # Cambios sensibles con FIRMAS de administradores (Tasas e impuestos,
  # documentos legales, revocaciones de acceso). Ver ChangeRequest.
  class ChangeRequestsController < ApplicationController
    include TokenAuthenticatable

    VIEWERS = %w[master admin sistema].freeze
    SIGNERS = %w[master admin].freeze

    # GET /api/change_requests -> pendientes + últimos resueltos
    def index
      return forbidden unless VIEWERS.include?(role_name)
      return migration_missing unless ChangeRequest.table_exists?

      pending = ChangeRequest.pending.order(created_at: :desc).includes(:change_signatures)
      recent = ChangeRequest.where.not(status: 'pending')
                            .order(updated_at: :desc).limit(20).includes(:change_signatures)
      render json: {
        me: @current_user.id,
        can_sign: SIGNERS.include?(role_name),
        pending: pending.map(&:as_api),
        recent: recent.map(&:as_api)
      }, status: :ok
    end

    # POST /api/change_requests/:id/sign
    def sign
      return forbidden unless SIGNERS.include?(role_name)
      return migration_missing unless ChangeRequest.table_exists?

      cr = ChangeRequest.find(params[:id])
      return render(json: { error: 'Este cambio ya no está pendiente.' }, status: :unprocessable_entity) unless cr.status == 'pending'
      if cr.target_user_id == @current_user.id
        return render(json: { error: 'No puedes firmar tu propia revocación de acceso.' }, status: :unprocessable_entity)
      end
      if cr.change_signatures.exists?(user_id: @current_user.id)
        return render(json: { error: 'Ya firmaste este cambio.' }, status: :unprocessable_entity)
      end

      cr.add_signature!(@current_user)
      render json: { ok: true, change_request: cr.reload.as_api }, status: :ok
    rescue ActiveRecord::RecordNotFound
      render json: { error: 'Cambio no encontrado' }, status: :not_found
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # POST /api/change_requests/:id/reject
    def reject
      return forbidden unless SIGNERS.include?(role_name)
      return migration_missing unless ChangeRequest.table_exists?

      cr = ChangeRequest.find(params[:id])
      return render(json: { error: 'Este cambio ya no está pendiente.' }, status: :unprocessable_entity) unless cr.status == 'pending'

      cr.reject!(@current_user)
      render json: { ok: true, change_request: cr.reload.as_api }, status: :ok
    rescue ActiveRecord::RecordNotFound
      render json: { error: 'Cambio no encontrado' }, status: :not_found
    end

    private

    def role_name
      @current_user&.role&.name
    end

    def forbidden
      render json: { error: 'No autorizado' }, status: :forbidden
    end

    def migration_missing
      render json: { error: 'Falta la migración de aprobaciones (bin/rails db:migrate).' }, status: :unprocessable_entity
    end
  end
end
