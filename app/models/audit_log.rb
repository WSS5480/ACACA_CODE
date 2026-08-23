# frozen_string_literal: true

# Registro de auditoría: quién hizo qué y cuándo. NUNCA debe romper la operación:
# si la tabla no existe todavía o algo falla, se ignora en silencio (solo log).
class AuditLog < ApplicationRecord
  ACTIONS = {
    'rates_updated'        => 'Cambió tasas e impuestos',
    'template_updated'     => 'Editó documento legal',
    'template_reset'       => 'Restauró documento legal',
    'payment_recorded'     => 'Registró pago (manual)',
    'payment_online'       => 'Pago en línea (Stripe)',
    'order_verified'       => 'Guardó verificación',
    'order_approved'       => 'Aprobó para compra',
    'order_delivered'      => 'Confirmó entrega',
    'contract_generated'   => 'Generó contrato para firma',
    'contract_signed'      => 'Firmó contrato',
    'contract_deleted'     => 'Eliminó contrato/pedido',
    'credit_set'           => 'Fijó línea de crédito',
    'client_deleted'       => 'Eliminó cliente',
    'due_date_moved'       => 'Movió vencimiento (pruebas)',
    'change_proposed'      => 'Propuso cambio (pendiente de firmas)',
    'change_signed'        => 'Firmó cambio propuesto',
    'change_rejected'      => 'Rechazó cambio propuesto',
    'staff_deleted'        => 'Revocó acceso de usuario del equipo',
    'contract_status_changed' => 'Cambió estado de cuenta (devuelto/castigado)',
    'marketing_post'       => 'Publicó en redes sociales',
    'marketing_library'    => 'Editó biblioteca de publicaciones',
    'wa_message_deleted'   => 'Eliminó mensaje de WhatsApp',
    'note_deleted'         => 'Eliminó nota de llamada',
    'thread_deleted'       => 'Eliminó conversación completa',
    'wa_template_created'  => 'Creó plantilla de WhatsApp',
    'wa_template_deleted'  => 'Eliminó plantilla de WhatsApp',
    'commitment_created'   => 'Registró compromiso de pago',
    'commitment_updated'   => 'Actualizó compromiso de pago',
    'lead_released'        => 'Liberó cuenta nueva del CRM',
    'questions_updated'    => 'Editó preguntas de aprobación',
    'wa_responses_updated' => 'Editó respuestas automáticas de WhatsApp',
    'auto_send_failed'     => '⚠ Falló un envío automático (alerta interna)',
    'autopay_all_changed'  => 'Cambió pago automático de toda la cuenta',
    'email_changed'        => 'Cambió el correo de la cuenta',
    'contract_frequency_changed' => 'Cambió frecuencia de pago del contrato',
    'ticket_created'       => 'Abrió ticket de soporte',
    'ticket_updated'       => 'Actualizó ticket de soporte',
    'ticket_resolved'      => '✅ Resolvió ticket de soporte',
    'duplicate_phone_signup' => '⚠ Registro con teléfono de otra cuenta verificada',
    'account_confirmed_manual' => '✔ Verificó cuenta manualmente (saltó WhatsApp)',
    'payment_refunded'     => '↩ Reembolsó pago a la forma de pago original',
    'catalog_issue'        => '⚠ Ronda del catálogo: producto con problema en Amazon'
  }.freeze

  def self.record!(actor:, action:, target: nil, label: nil, details: nil)
    return unless table_exists?

    create!(
      user_id: actor&.id,
      user_email: actor&.email,
      user_role: (actor.respond_to?(:role) ? actor&.role&.name : nil),
      action: action.to_s,
      target_type: target&.class&.name,
      target_id: target&.id,
      target_label: label.to_s.presence,
      details: details.to_s.presence,
      created_at: Time.current
    )
  rescue StandardError => e
    Rails.logger.warn "[audit] no se pudo registrar #{action}: #{e.message}"
    nil
  end
end
