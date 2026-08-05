# frozen_string_literal: true

module Api
  # Bitácora de auditoría (solo master/admin): quién hizo qué, filtrable por usuario y acción.
  class AuditLogsController < ApplicationController
    include TokenAuthenticatable

    def index
      unless %w[master admin].include?(@current_user&.role&.name)
        return render json: { error: 'No autorizado' }, status: :forbidden
      end
      unless AuditLog.table_exists?
        return render json: { error: 'Falta la migración de la bitácora (bin/rails db:migrate).' }, status: :unprocessable_entity
      end

      logs = AuditLog.order(created_at: :desc)
      logs = logs.where(user_id: params[:user_id]) if params[:user_id].present?
      logs = logs.where(action: params[:action_key]) if params[:action_key].present?
      if params[:q].present?
        q = "%#{params[:q]}%"
        logs = logs.where('target_label ILIKE :q OR details ILIKE :q OR user_email ILIKE :q', q: q)
      end
      logs = logs.limit(500)
      render json: {
        actions: AuditLog::ACTIONS,
        logs: logs.map do |l|
          { id: l.id, user_id: l.user_id, user_email: l.user_email, user_role: l.user_role,
            action: l.action, action_label: AuditLog::ACTIONS[l.action] || l.action,
            target_type: l.target_type, target_id: l.target_id, target_label: l.target_label,
            details: l.details, created_at: l.created_at }
        end
      }, status: :ok
    end
  end
end
