# frozen_string_literal: true

# Compromiso de pago acordado con el cliente.
# 1) Al registrarlo se le manda un WhatsApp de confirmación.
# 2) El DÍA ANTERIOR a la fecha, la plataforma manda sola el recordatorio.
# Ambos mensajes usan plantilla aprobada si la ventana de 24 h está cerrada,
# y quedan archivados en la conversación de la persona.
class PaymentCommitment < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :contract, optional: true

  validates :due_on, presence: true
  validates :amount, numericality: { greater_than: 0 }, allow_nil: true

  scope :pending, -> { where(status: 'pending') }

  def money
    format('$%.2f', amount.to_f)
  end

  def label
    [person_name.presence, money, "para el #{I18n.l(due_on, format: :long) rescue due_on.to_s}"].compact.join(' · ')
  end

  def target_phone
    phone.presence || user&.phone
  end

  def front
    (ENV['FRONT_HOST'].presence || 'https://www.acasamx.com').chomp('/')
  end

  # Aviso inmediato: "queda registrado tu compromiso".
  def send_confirmation!(actor: nil)
    return { ok: false, error: 'Sin teléfono' } if target_phone.blank?

    fecha = due_on.strftime('%d/%m/%Y')
    link = "#{front}/cuenta"
    txt = "Hola #{first_name}, gracias por tu llamada. Queda registrado tu compromiso de pago de #{money} " \
          "para el #{fecha}. Puedes pagar en línea desde tu cuenta: #{link}"
    r = WhatsappOutbound.deliver(phone: target_phone, text: txt, event: 'pago',
                                 params: [first_name, money, contract_ref, link],
                                 user: user, actor: actor)
    update_columns(confirmed_at: Time.current) if r[:ok]
    log!(txt, actor)
    r
  end

  # Recordatorio automático del día anterior.
  def send_reminder!
    return { ok: false, error: 'Sin teléfono' } if target_phone.blank?

    fecha = due_on.strftime('%d/%m/%Y')
    link = "#{front}/cuenta"
    txt = "Hola #{first_name}, te recordamos tu compromiso de pago de #{money} para mañana #{fecha}. " \
          "Puedes pagar en línea desde tu cuenta: #{link} ¿Alguna duda? Responde por aquí."
    r = WhatsappOutbound.deliver(phone: target_phone, text: txt, event: 'pago',
                                 params: [first_name, money, contract_ref, link],
                                 user: user, actor: nil)
    update_columns(reminded_at: Time.current) if r[:ok]
    log!("(automático) #{txt}", nil)
    r
  end

  # Manda los recordatorios de MAÑANA. Lo llama el job diario.
  def self.run_reminders!(for_date: Date.current + 1)
    sent = 0
    errors = []
    pending.where(due_on: for_date, reminded_at: nil).find_each do |c|
      r = c.send_reminder!
      r[:ok] ? sent += 1 : errors << "##{c.id}: #{r[:error]}"
    end
    { date: for_date.to_s, sent: sent, errors: errors }
  end

  private

  def first_name
    (person_name.presence || user&.name.to_s).to_s.strip.split(' ').first.presence || 'cliente'
  end

  def contract_ref
    contract&.contract_number.presence || contract&.order_ref.presence || 'tu cuenta'
  end

  def log!(txt, actor)
    ContactLog.create!(user_id: user_id, person_type: 'customer',
                       person_name: person_name.presence || [user&.name, user&.last_name].compact.join(' ').presence,
                       phone: target_phone.to_s.gsub(/\D/, '').presence,
                       body: "🤝 COMPROMISO #{money} para el #{due_on.strftime('%d/%m/%Y')} · aviso enviado",
                       author_id: actor&.id,
                       author_name: [actor&.name, actor&.last_name].compact.join(' ').strip.presence || 'Automático')
  rescue StandardError => e
    Rails.logger.warn "[PaymentCommitment] log: #{e.message}"
  end
end
