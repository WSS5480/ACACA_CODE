# frozen_string_literal: true

# Revisión de números telefónicos ANTES de guardarlos: un número mal capturado
# (un dígito de menos, lada inexistente) se acepta en Meta y NUNCA se entrega.
# Aquí se detecta al momento de escribirlo.
#
# Compradores en CUALQUIER país: el número llega en formato internacional
# (+lada y dígitos). Se reconoce el país por la lada (PhoneGeo) y se revisa la
# longitud NACIONAL típica de ese país; para países sin tabla, 6–14 dígitos.
# Compatibilidad: 10 dígitos sin '+' = EE. UU./Canadá (convención histórica).
class PhoneCheck
  US_AREA = /\A[2-9]\d{2}[2-9]\d{6}\z/ # lada y prefijo válidos del plan norteamericano

  # Devuelve nil si está bien, o el motivo del problema.
  def self.problem(raw)
    s = raw.to_s.strip
    return nil if s.blank?

    d = s.gsub(/\D/, '')
    return 'El teléfono no tiene números' if d.blank?
    return 'El teléfono es demasiado largo' if d.length > 15

    dial = PhoneGeo.dial_of(s)
    return 'No reconocemos la lada de ese número; escríbelo con el signo + y el código de tu país' if dial.blank?

    iso = PhoneGeo.country_of(s)
    nat = national_digits(s, d, dial)

    case dial
    when '+52'
      nat = nat.sub(/\A1/, '') if nat.length == 11 # algunos traen el 1 de móvil
      return "México necesita 10 dígitos (tiene #{nat.length})" unless nat.length == 10
    when '+1'
      return "Un número de #{PhoneGeo.name(iso).presence || 'EE. UU.'} son 10 dígitos (tiene #{nat.length})" unless nat.length == 10
      return 'La lada no es válida (no puede empezar con 0 ni 1)' unless nat.match?(US_AREA)
    else
      min, max = PhoneGeo::NATIONAL_LENGTH[iso] || [6, 14]
      unless nat.length.between?(min, max)
        esperado = min == max ? "#{min} dígitos" : "entre #{min} y #{max} dígitos"
        return "Un número de #{PhoneGeo.name(iso).presence || iso} son #{esperado} después de la lada #{dial} (tiene #{nat.length})"
      end
    end

    nil
  end

  def self.valid?(raw)
    problem(raw).nil?
  end

  # Dígitos SIN la lada. Números históricos sin '+': 10 dígitos = EE. UU. tal cual.
  def self.national_digits(raw, digits, dial)
    code = dial.delete('+')
    return digits if !raw.start_with?('+', '00') && dial == '+1' && digits.length == 10

    digits.sub(/\A00/, '').sub(/\A#{code}/, '')
  end
end
