# frozen_string_literal: true

# Revisión de números telefónicos ANTES de guardarlos: un número mal capturado
# (un dígito de menos, lada inexistente) se acepta en Meta y NUNCA se entrega.
# Aquí se detecta al momento de escribirlo.
#
# Reglas: EE.UU./Canadá = 10 dígitos (la lada 1 la agrega WhatsApp sola, por eso
# se guarda sin ella). México = +52 y 10 dígitos. Otros países: +lada y 8 a 14.
class PhoneCheck
  US_AREA = /\A[2-9]\d{2}[2-9]\d{6}\z/ # lada y prefijo válidos de EE.UU.

  # Devuelve nil si está bien, o el motivo del problema.
  def self.problem(raw)
    s = raw.to_s.strip
    return nil if s.blank?

    d = s.gsub(/\D/, '')
    return 'El teléfono no tiene números' if d.blank?

    if s.start_with?('+52') || d.start_with?('52')
      nat = d.sub(/\A52/, '').sub(/\A1/, '') # algunos traen el 1 de móvil
      return "México necesita 10 dígitos (tiene #{nat.length})" unless nat.length == 10

      return nil
    end

    if s.start_with?('+') && !s.start_with?('+1')
      return 'Número internacional demasiado corto' if d.length < 8
      return 'Número internacional demasiado largo' if d.length > 15

      return nil
    end

    # EE.UU./Canadá (con o sin el 1 al frente)
    nat = d.sub(/\A1/, '')
    return "Un número de EE.UU. son 10 dígitos (tiene #{nat.length})" unless nat.length == 10
    return 'La lada de EE.UU. no es válida (no puede empezar con 0 ni 1)' unless nat.match?(US_AREA)

    nil
  end

  def self.valid?(raw)
    problem(raw).nil?
  end
end
