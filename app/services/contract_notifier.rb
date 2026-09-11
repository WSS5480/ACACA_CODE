# frozen_string_literal: true

# CORREOS AL CLIENTE después del pago inicial: un RECIBO por cada pago y un
# aviso por cada ETAPA del proceso (datos recibidos → verificado → aprobado →
# firmado → entregado). Un solo lugar decide qué se manda y cuándo; cada etapa
# se envía UNA vez por contrato (contracts.stage_emails guarda cuándo salió).
# Nunca rompe el flujo que lo llama: cualquier error se registra y se sigue.
class ContractNotifier
  STAGES = %w[datos_recibidos verificado aprobado firmado entregado].freeze
  VERIFIED_FLAGS = %i[beneficiary_verified buyer_verified residency_verified employment_verified references_verified].freeze

  class << self
    # RECIBO por CADA pago: inicial, cuotas, pagos combinados, autopago y
    # pagos registrados a mano por el equipo. Incluye el calendario de pagos.
    def payment_received(payment)
      contract = payment&.contract
      user = contract&.user
      return if user&.email.blank?

      UserMailer.with(user: user, contract: contract, payment: payment).send_payment_receipt.deliver_now
      log(contract, "Recibo REC-#{payment.id} enviado a #{user.email}")
    rescue StandardError => e
      Rails.logger.error "[ContractNotifier] recibo pago #{payment&.id}: #{e.class}: #{e.message}"
    end

    # Después de guardar comprador o referencias (o de confirmar los datos de
    # una compra anterior): expediente completo + pago inicial hecho → aviso.
    def check_datos(contract)
      return unless contract

      contract = contract.reload
      return unless contract.initial_paid? && contract.datos_complete?

      stage!(contract, 'datos_recibidos')
    rescue StandardError => e
      Rails.logger.error "[ContractNotifier] check_datos contrato #{contract&.id}: #{e.message}"
    end

    # Después de guardar la verificación en Órdenes. Las 5 secciones palomeadas
    # → "verificado"; aprobación final → "aprobado" (si llegan juntas, solo se
    # manda el de aprobación y el de verificación se da por cubierto).
    def check_verification(order)
      contract = order&.contract
      return unless contract

      os = contract.orders.to_a
      return if os.empty?

      approved = os.all? { |o| o.respond_to?(:admin_approved) && o.admin_approved }
      verified = os.all? { |o| VERIFIED_FLAGS.all? { |f| o.respond_to?(f) && o.public_send(f) } }
      if approved
        stage!(contract, 'verificado', send_mail: false)
        stage!(contract, 'aprobado')
      elsif verified
        stage!(contract, 'verificado')
      end
    rescue StandardError => e
      Rails.logger.error "[ContractNotifier] check_verification orden #{order&.id}: #{e.message}"
    end

    # El cliente firmó su contrato.
    def signed(contract)
      stage!(contract, 'firmado')
    end

    # Entrega confirmada: cuando TODOS los artículos del pedido están entregados.
    def check_delivery(order)
      contract = order&.contract
      return unless contract

      os = contract.orders.to_a
      return if os.empty? || !os.all? { |o| o.respond_to?(:delivered_at) && o.delivered_at.present? }

      stage!(contract, 'entregado')
    rescue StandardError => e
      Rails.logger.error "[ContractNotifier] check_delivery orden #{order&.id}: #{e.message}"
    end

    # Manda el correo de una etapa UNA sola vez por contrato.
    def stage!(contract, key, send_mail: true)
      return false unless contract && STAGES.include?(key)
      return false if sent?(contract, key)

      user = contract.user
      if send_mail
        return false if user&.email.blank?

        UserMailer.with(user: user, contract: contract, stage: key).send_stage_update.deliver_now
      end
      mark!(contract, key)
      log(contract, send_mail ? "Correo de etapa '#{key}' enviado a #{user.email}" : "Etapa '#{key}' cubierta por el aviso de aprobación")
      true
    rescue StandardError => e
      Rails.logger.error "[ContractNotifier] etapa #{key} contrato #{contract&.id}: #{e.class}: #{e.message}"
      false
    end

    private

    def stage_column?
      Contract.column_names.include?('stage_emails')
    end

    def sent?(contract, key)
      return (contract.stage_emails || {}).key?(key) if stage_column?

      # Sin la columna (migración pendiente): la bitácora evita el doble envío.
      AuditLog.table_exists? && AuditLog.where(action: 'stage_email', target_type: 'Contract', target_id: contract.id)
                                        .where('details LIKE ?', "%'#{key}'%").exists?
    end

    def mark!(contract, key)
      return unless stage_column?

      contract.update_column(:stage_emails, (contract.stage_emails || {}).merge(key => Time.current.iso8601))
    end

    def log(contract, details)
      AuditLog.record!(actor: nil, action: 'stage_email', target: contract,
                       label: (contract.contract_number.presence || contract.order_ref), details: details)
    rescue StandardError => e
      Rails.logger.warn "[ContractNotifier] bitácora: #{e.message}"
    end
  end
end
