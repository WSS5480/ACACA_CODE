# frozen_string_literal: true

# TICKET de soporte: una solicitud de ayuda por cliente, gestionada hasta su
# resolución. Estados: abierto -> en_proceso -> esperando_cliente -> resuelto
# (se puede REABRIR). Prioridades: baja / media / alta.
class SupportTicket < ApplicationRecord
  belongs_to :user, optional: true
  has_many :notes, class_name: 'SupportTicketNote', dependent: :destroy

  STATUSES = %w[abierto en_proceso esperando_cliente resuelto].freeze
  PRIORITIES = %w[baja media alta].freeze

  validates :subject, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :priority, inclusion: { in: PRIORITIES }

  scope :open_ones, -> { where.not(status: 'resuelto') }

  def ref
    "T-#{id}"
  end

  # 🆘 Auto-ticket desde el botón de Soporte del sitio: al llegar el saludo de
  # ayuda por WhatsApp se abre un ticket (si el teléfono no tiene ya uno abierto).
  def self.log_from_whatsapp!(from:, body:, user: nil)
    return unless table_exists?

    digits = from.to_s.gsub(/\D/, '')
    tail = digits[-10..]
    return if tail.blank?

    existing = open_ones.where("regexp_replace(coalesce(phone,''), '[^0-9]', '', 'g') LIKE ?", "%#{tail}")
                        .order(:id).last
    if existing
      # Ya hay un ticket ABIERTO de este número: el nuevo mensaje se anota ahí
      # (sin duplicar tickets), el ticket sube al frente y el cliente recibe un
      # "sigue en proceso" (texto editable: 'soporte_en_proceso').
      existing.notes.create!(author_name: 'Automático', body: "💬 El cliente volvió a escribir: “#{body.to_s[0, 300]}”")
      existing.touch
      begin
        nombre = existing.customer_name.to_s.split.first.presence || 'hola'
        WhatsappOutbound.deliver(phone: digits,
                                 text: WaAutoText.render('soporte_en_proceso', nombre: nombre, ticket: existing.ref),
                                 user: user || existing.user)
      rescue StandardError => e
        Rails.logger.warn "[SupportTicket] en_proceso: #{e.message}"
      end
      return existing
    end

    name = user ? [user.name, user.last_name].compact.join(' ').strip.presence : nil
    t = create!(user_id: user&.id, customer_name: name || "WhatsApp #{from}", phone: digits,
                subject: 'Solicitud de ayuda por WhatsApp', description: body.to_s[0, 1000],
                channel: 'whatsapp', created_by: 'Automático')
    t.notes.create!(author_name: 'Automático', body: "🆘 El cliente escribió desde la página de Soporte: “#{body.to_s[0, 300]}”")
    AuditLog.record!(actor: nil, action: 'ticket_created', target: t, label: t.ref,
                     details: "Auto-ticket de WhatsApp · #{t.customer_name}")
    # Acuse INMEDIATO al cliente (su ventana está abierta: nos acaba de escribir).
    # Texto EDITABLE en Respuestas WhatsApp ('soporte_recibido').
    begin
      nombre = name.to_s.split.first.presence || 'hola'
      ack = WaAutoText.render('soporte_recibido', nombre: nombre, ticket: t.ref)
      WhatsappOutbound.deliver(phone: digits, text: ack, user: user)
    rescue StandardError => e
      Rails.logger.warn "[SupportTicket] acuse: #{e.message}"
    end
    t
  rescue StandardError => e
    Rails.logger.warn "[SupportTicket] auto: #{e.message}"
    nil
  end
end
