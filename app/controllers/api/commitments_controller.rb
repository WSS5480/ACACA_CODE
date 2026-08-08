# frozen_string_literal: true

module Api
  # COMPROMISOS DE PAGO (cobranza): registrar el acuerdo, avisar al cliente al
  # momento y dejar programado el recordatorio del día anterior.
  class CommitmentsController < ApplicationController
    include TokenAuthenticatable

    STAFF = %w[master admin sistema editor operador gerente admin_cuentas].freeze
    before_action :authorize_staff!, except: [:run_reminders]

    # GET /api/commitments?user_id=
    def index
      scope = PaymentCommitment.all
      scope = scope.where(user_id: params[:user_id]) if params[:user_id].present?
      render json: { commitments: scope.order(due_on: :desc).limit(200).map { |c| serialize(c) } }, status: :ok
    end

    # POST /api/commitments { user_id, contract_id, amount, due_on, note, phone, person_name, notify }
    def create
      due = begin
        Date.parse(params[:due_on].to_s)
      rescue StandardError
        nil
      end
      return render(json: { error: 'Fecha del compromiso inválida' }, status: :unprocessable_entity) unless due
      return render(json: { error: 'El monto debe ser mayor a cero' }, status: :unprocessable_entity) unless params[:amount].to_f.positive?

      c = PaymentCommitment.create!(
        user_id: params[:user_id].presence, contract_id: params[:contract_id].presence,
        amount: params[:amount].to_f.round(2), due_on: due,
        phone: params[:phone].to_s.presence, person_name: params[:person_name].to_s.presence,
        note: params[:note].to_s.presence, status: 'pending',
        created_by_id: @current_user&.id,
        created_by_name: [@current_user&.name, @current_user&.last_name].compact.join(' ').strip.presence || @current_user&.email
      )
      AuditLog.record!(actor: @current_user, action: 'commitment_created', target: c,
                       label: c.person_name.to_s, details: "#{c.money} para el #{c.due_on}")

      notify = params.key?(:notify) ? ActiveModel::Type::Boolean.new.cast(params[:notify]) : true
      msg = notify ? c.send_confirmation!(actor: @current_user) : { ok: false, skipped: true }
      render json: { ok: true, commitment: serialize(c), aviso: msg }, status: :created
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end

    # PUT /api/commitments/:id { status } -> kept | broken | cancelled
    def update
      c = PaymentCommitment.find(params[:id])
      st = params[:status].to_s
      return render(json: { error: 'Estado inválido' }, status: :unprocessable_entity) unless %w[pending kept broken cancelled].include?(st)

      c.update!(status: st)
      AuditLog.record!(actor: @current_user, action: 'commitment_updated', target: c,
                       label: c.person_name.to_s, details: "#{c.money} · #{st}")
      render json: { ok: true, commitment: serialize(c) }, status: :ok
    rescue ActiveRecord::RecordNotFound
      render json: { error: 'Compromiso no encontrado' }, status: :not_found
    end

    # POST /api/commitments/run_reminders  (cron externo con X-Autopay-Token, o staff)
    def run_reminders
      secret = ENV['AUTOPAY_SECRET']
      by_token = secret.present? && ActiveSupport::SecurityUtils.secure_compare(request.headers['X-Autopay-Token'].to_s, secret)
      unless by_token || STAFF.include?(@current_user&.role&.name)
        return render(json: { error: 'No autorizado' }, status: :forbidden)
      end

      render json: PaymentCommitment.run_reminders!(for_date: (Date.parse(params[:date].to_s) rescue Date.current + 1)), status: :ok
    end

    private

    def serialize(c)
      { id: c.id, user_id: c.user_id, contract_id: c.contract_id, amount: c.amount,
        due_on: c.due_on, status: c.status, note: c.note,
        confirmed_at: c.confirmed_at, reminded_at: c.reminded_at,
        created_by_name: c.created_by_name, created_at: c.created_at }
    end

    def authorize_staff!
      return if STAFF.include?(@current_user&.role&.name)

      render json: { error: 'No autorizado' }, status: :forbidden
    end
  end
end
