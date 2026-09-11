# frozen_string_literal: true

# Formato para los CORREOS: dinero siempre como $1,234.56 (punto decimal y
# coma de miles, sin importar el idioma del servidor) y fechas en español en
# la hora de México.
module MailFormatHelper
  MESES = %w[ene feb mar abr may jun jul ago sep oct nov dic].freeze

  def mail_money(v)
    n = v.to_f
    whole, cents = format('%.2f', n.abs).split('.')
    "#{n.negative? ? '-' : ''}$#{whole.reverse.scan(/\d{1,3}/).join(',').reverse}.#{cents}"
  end

  def mail_date(d)
    return '—' if d.blank?

    d = d.to_date
    "#{d.day} #{MESES[d.month - 1]} #{d.year}"
  end

  def mail_datetime(t)
    return '—' if t.blank?

    t = t.in_time_zone(Time.zone)
    "#{mail_date(t)}, #{t.strftime('%H:%M')} h"
  end

  def mail_kind_label(kind)
    { 'enganche' => 'Pago inicial (enganche + primera cuota)', 'renta' => 'Pago de cuota',
      'contado' => 'Pago de contado', 'liquidacion' => 'Liquidación', 'epo' => 'Compra anticipada' }[kind.to_s] || 'Pago'
  end

  def mail_method_label(m)
    %w[stripe autopay].include?(m.to_s) ? 'Tarjeta' : (m.to_s.presence || '—')
  end

  def mail_freq_label(f)
    { 'weekly' => 'Semanal (sábados)', 'biweekly' => 'Quincenal (sábados)', 'monthly' => 'Mensual (día 1)' }[f.to_s] || 'Semanal'
  end

  def mail_status_label(s)
    { 'paid' => 'Pagado', 'partial' => 'Parcial' }[s.to_s] || 'Pendiente'
  end
end
