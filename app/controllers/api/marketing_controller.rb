# frozen_string_literal: true

module Api
  # Marketing en redes (pestaña Marketing del admin): Facebook + Instagram.
  # Publicar/programar, ver publicaciones y comentarios, responder y métricas.
  # Acceso: master, admin, sistema y Administrador de Redes sociales.
  class MarketingController < ApplicationController
    include TokenAuthenticatable

    ROLES = %w[master admin sistema admin_redes].freeze

    before_action :authorize_mkt!

    # GET /api/marketing/overview
    def overview
      svc = MetaMarketing.new
      render json: svc.overview.merge(configured: true), status: :ok
    rescue MetaMarketing::NotConfigured => e
      render json: { configured: false, error: e.message }, status: :ok
    rescue StandardError => e
      render json: { configured: true, error: e.message }, status: :ok
    end

    # GET /api/marketing/posts
    def posts
      render json: { posts: MetaMarketing.new.posts }, status: :ok
    rescue StandardError => e
      render json: { posts: [], error: e.message }, status: :ok
    end

    # GET /api/marketing/comments
    def comments
      render json: { comments: MetaMarketing.new.comments }, status: :ok
    rescue StandardError => e
      render json: { comments: [], error: e.message }, status: :ok
    end

    # POST /api/marketing/publish { message, image_url, networks:['fb','ig'], scheduled_at }
    def publish
      message = params[:message].to_s.strip
      image = params[:image_url].to_s.strip.presence
      networks = Array(params[:networks]).map(&:to_s) & %w[fb ig]
      return render(json: { error: 'Escribe el texto de la publicación.' }, status: :unprocessable_entity) if message.blank? && image.blank?
      return render(json: { error: 'Elige al menos una red (Facebook o Instagram).' }, status: :unprocessable_entity) if networks.empty?

      scheduled = nil
      if params[:scheduled_at].present?
        scheduled = Time.zone.parse(params[:scheduled_at].to_s) rescue nil
        return render(json: { error: 'La fecha programada debe ser al menos 10 minutos en el futuro.' }, status: :unprocessable_entity) if scheduled.nil? || scheduled < 10.minutes.from_now
      end

      results = MetaMarketing.new.publish(message: message, image_url: image, networks: networks, scheduled_at: scheduled)
      ok_nets = results.select { |_k, v| v.is_a?(Hash) && v['id'].present? }.keys
      AuditLog.record!(actor: @current_user, action: 'marketing_post',
                       label: "Redes: #{ok_nets.map(&:to_s).join('+').presence || 'sin éxito'}",
                       details: "#{scheduled ? "PROGRAMADO #{scheduled.strftime('%d/%m %H:%M')} · " : ''}#{message[0, 120]}")
      render json: { ok: ok_nets.any?, results: results }, status: :ok
    rescue MetaMarketing::NotConfigured => e
      render json: { error: e.message }, status: :unprocessable_entity
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # POST /api/marketing/reply { comment_id, network, message }
    def reply
      msg = params[:message].to_s.strip
      return render(json: { error: 'Escribe la respuesta.' }, status: :unprocessable_entity) if msg.blank?

      r = MetaMarketing.new.reply(comment_id: params[:comment_id].to_s, message: msg, network: params[:network].to_s)
      if r['id'].present?
        render json: { ok: true }, status: :ok
      else
        render json: { error: r.dig('error', 'message') || 'No se pudo responder.' }, status: :unprocessable_entity
      end
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    private

    def authorize_mkt!
      return if ROLES.include?(@current_user&.role&.name)

      render json: { error: 'No autorizado' }, status: :forbidden
    end
  end
end
