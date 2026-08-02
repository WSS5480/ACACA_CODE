# frozen_string_literal: true

module Api
  class ContractsController < ApplicationController
    include TokenAuthenticatable

    before_action :authorize_staff!, only: [:create, :record_payment]

    # GET /api/contracts?user_id=
    def index
      scope = Contract.includes(:user).order(created_at: :desc)
      scope = scope.where(user_id: params[:user_id]) if params[:user_id].present?
      render json: ContractSerializer.new(scope).serializable_hash, status: :ok
    end

    # GET /api/contracts/:id  -> contrato + articulos + tabla de amortizacion
    def show
      contract = Contract.includes(:user, :orders, :contract_installments).find(params[:id])
      data = ContractSerializer.new(contract).serializable_hash[:data][:attributes]
      data[:items] = contract.orders.map { |o| OrderSerializer.new(o).serializable_hash[:data][:attributes] }
      data[:installments] = contract.contract_installments.map { |i| ContractInstallmentSerializer.new(i).serializable_hash[:data][:attributes] }
      render json: { data: data }, status: :ok
    rescue ActiveRecord::RecordNotFound
      render json: { error: 'Contrato no encontrado' }, status: :not_found
    end

    # POST /api/contracts  { user_id, product_ids:[], downpayment, weeks }
    # Crea un contrato con UNO O VARIOS articulos y UN pago semanal combinado.
    def create
      user = User.find_by(id: params[:user_id])
      return render(json: { error: 'Usuario no encontrado' }, status: :not_found) unless user

      product_ids = Array(params[:product_ids]).map(&:to_i).reject(&:zero?)
      products = Product.where(id: product_ids).to_a
      return render(json: { error: 'Selecciona al menos un producto' }, status: :unprocessable_entity) if products.empty?

      weeks = params[:weeks].to_i
      return render(json: { error: 'Plazo (semanas) invalido' }, status: :unprocessable_entity) if weeks <= 0

      total = products.sum { |p| p.total_price.to_f }.round(2)
      down = params[:downpayment].to_f
      financed = (total - down).round(2)
      return render(json: { error: 'El enganche no puede ser mayor al total' }, status: :unprocessable_entity) if financed < 0

      available = user.credit&.amount.to_f
      return render(json: { error: 'El cliente no tiene suficiente credito disponible' }, status: :unprocessable_entity) if financed > available + 0.01

      weekly = (financed / weeks).round(2)

      contract = nil
      ActiveRecord::Base.transaction do
        contract = Contract.create!(
          user: user, status: 'active',
          total_amount: total, downpayment: down, financed_amount: financed,
          weekly_payment: weekly, weeks: weeks, start_date: Date.current
        )
        products.each do |prod|
          contract.orders.create!(
            user_id: user.id, product_id: prod.id,
            user_name: user.name, user_last_name: user.last_name, user_email: user.email,
            product_title: prod.title, product_asin: prod.asin,
            product_price: prod.price, product_price_with_discount: prod.price_with_discount,
            product_original_price: prod.original_price,
            product_turns: prod.turns, product_decimal_factor: prod.decimal_factor,
            used_credit: 0, downpayment: 0, weekly_payment: 0, credit_duration: weeks,
            status: 'approved'
          )
        end
        if user.credit.present? && financed > 0
          user.credit.update!(amount: (user.credit.amount - financed).round(2))
        end
        contract.build_amortization!
      end

      render json: { data: ContractSerializer.new(contract).serializable_hash[:data][:attributes] }, status: :created
    rescue ActiveRecord::RecordInvalid => e
      render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # POST /api/contracts/:id/record_payment  { amount, method, note }
    def record_payment
      contract = Contract.find(params[:id])
      amount = params[:amount].to_f
      return render(json: { error: 'Monto invalido' }, status: :unprocessable_entity) if amount <= 0

      contract.payments.create!(amount: amount, method: params[:method], note: params[:note])
      contract.reload
      render json: {
        ok: true,
        balance: contract.balance,
        payment_status: contract.payment_status,
        available_credit: contract.user&.available_credit
      }, status: :ok
    rescue ActiveRecord::RecordNotFound
      render json: { error: 'Contrato no encontrado' }, status: :not_found
    rescue ActiveRecord::RecordInvalid => e
      render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
    end

    private

    def authorize_staff!
      role = @current_user&.role&.name
      return if %w[master admin].include?(role)
      render json: { error: 'No autorizado' }, status: :forbidden
    end
  end
end
