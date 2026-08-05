# frozen_string_literal: true

# Genera el TEXTO del contrato de un cliente: toma la plantilla editable
# (Seguridad → Control de documentos legales) y rellena los campos {{...}}
# con los datos reales del contrato, el cliente, el comprador, el beneficiario
# y la tabla de pagos (Anexo A).
class ContractDocument
  TEMPLATE_KEY = 'contract_template'

  FREQ_ADJ = { 'weekly' => 'Semanal', 'biweekly' => 'Quincenal', 'monthly' => 'Mensual' }.freeze

  def self.template
    AppSetting.get(TEMPLATE_KEY).presence || begin
      path = Rails.root.join('db', 'templates', 'contract_template.txt')
      File.exist?(path) ? File.read(path) : ''
    end
  end

  def self.render(contract)
    new(contract).render
  end

  def initialize(contract)
    @c = contract
    @user = contract.user
    @orders = contract.orders.to_a
    @buyer = @orders.filter_map { |o| o.respond_to?(:buyer) ? o.buyer : nil }.first
    @beneficiary = @orders.filter_map(&:beneficiary).first || @user&.beneficiaries&.first
    @guarantor = @orders.filter_map { |o| o.respond_to?(:guarantor) ? o.guarantor : nil }.first
  end

  def render
    tpl = self.class.template
    data = fields
    tpl.gsub(/\{\{(\w+)\}\}/) do
      key = Regexp.last_match(1)
      val = data[key]
      val.nil? || val.to_s.strip.empty? ? '________' : val.to_s
    end
  end

  private

  def money(v)
    format('%.2f', v.to_f)
  end

  def fdate(d)
    d ? d.strftime('%d/%m/%Y') : nil
  end

  def full_name(rec)
    return nil unless rec
    [rec.name, rec.last_name].compact.join(' ').strip.presence
  end

  def fields
    waiver_pct = @orders.first&.waiver.to_f
    per = @c.respond_to?(:period_payment) ? @c.period_payment : @c.weekly_payment.to_f
    exencion = waiver_pct.positive? ? (per * waiver_pct / 100.0).round(2) : nil
    n_pagos = @c.contract_installments.count
    n_pagos = @c.weeks.to_i if n_pagos.zero?

    {
      'numero_contrato' => @c.contract_number,
      'fecha_contrato' => fdate(@c.created_at&.to_date || Date.current),

      'comprador_nombre' => full_name(@buyer) || full_name(@user),
      'comprador_rfc' => nil,
      'comprador_direccion' => buyer_address,
      'comprador_telefono' => @buyer&.phone.presence || @user&.phone,
      'comprador_email' => @buyer&.email.presence || @user&.email,

      'obligado_nombre' => full_name(@guarantor),
      'obligado_rfc' => nil,
      'obligado_direccion' => guarantor_address,
      'obligado_telefono' => @guarantor&.phone,
      'obligado_email' => @guarantor&.email,

      'bien_numero' => @orders.size.to_s,
      'bien_descripcion' => @orders.each_with_index.map { |o, i| "#{i + 1}) #{o.product_title} (ASIN #{o.product_asin})" }.join('  '),
      'bien_serie' => nil,
      'bien_modelo' => nil,

      'monto_contado' => money(@c.total_amount),
      'monto_enganche' => money(@c.downpayment),
      'monto_credito' => money(@c.financed_amount),
      'monto_pago' => money(per),
      'periodicidad' => FREQ_ADJ[@c.freq] || 'Semanal',
      'numero_pagos' => n_pagos.to_s,
      'monto_total' => money(@c.downpayment.to_f + @c.financed_amount.to_f),
      'monto_exencion' => exencion ? money(exencion) : '0.00',
      'cuota_procesamiento' => (Product.processing_fee.positive? ? money(Product.processing_fee) : '0.00'),
      # TASA ANUAL calculada del contrato: (interés ÷ principal) anualizada por el plazo.
      'tasa_ordinaria' => (@c.respond_to?(:annual_interest_rate) && @c.annual_interest_rate.positive? ? format('%g', @c.annual_interest_rate) : format('%g', (@c.respond_to?(:interest_rate) ? @c.interest_rate : 25.0))),
      'tasa_moratoria' => (Product.mora_rate.positive? ? format('%g', Product.mora_rate) : nil),
      'descuento_anticipado' => nil,
      # CAT calculado del contrato (efectivo; incluye cuota de procesamiento, sin seguro opcional).
      'cat' => (@c.respond_to?(:computed_cat) && @c.computed_cat.positive? ? format('%g', @c.computed_cat) : nil),

      'moneda_mxn' => ' ',
      'moneda_usd' => 'X',
      'exencion_si' => waiver_pct.positive? ? 'X' : ' ',
      'exencion_no' => waiver_pct.positive? ? ' ' : 'X',
      'mercadeo_si' => 'X',
      'mercadeo_no' => ' ',

      'entrega_calle' => @beneficiary&.address1,
      'entrega_num_ext' => nil,
      'entrega_num_int' => nil,
      'entrega_colonia' => @beneficiary&.address2,
      'entrega_ciudad' => @beneficiary&.city,
      'entrega_estado' => @beneficiary&.state,
      'entrega_cp' => @beneficiary&.zip_code,
      'entrega_recibe' => full_name(@beneficiary),

      'tabla_pagos' => payment_table(exencion)
    }
  end

  def buyer_address
    if @buyer
      [@buyer.living_address1, @buyer.living_address2, @buyer.living_city, @buyer.living_state, @buyer.living_zip_code].compact.reject(&:empty?).join(', ').presence
    end
  end

  def guarantor_address
    if @guarantor
      [@guarantor.address1, @guarantor.address2, @guarantor.city, @guarantor.state, @guarantor.zip_code].compact.reject(&:empty?).join(', ').presence
    end
  end

  # Anexo A en texto de ancho fijo: # | fecha | pago | exención | total | saldo restante.
  def payment_table(exencion)
    rows = @c.contract_installments.order(:number).to_a
    return '(Sin tabla de pagos: el calendario se genera al activarse el contrato.)' if rows.empty?

    tax = Product.respond_to?(:tax_rate) ? Product.tax_rate : 0.0
    header = format('%4s  %-12s %16s %16s %16s %16s', '#', 'FECHA', 'PAGO CON IVA', 'EXENCION C/IVA', 'TOTAL CON IVA', 'SALDO DESPUES')
    saldo = @c.financed_amount.to_f
    lines = rows.map do |i|
      saldo = (saldo - i.amount.to_f).round(2)
      saldo = 0 if saldo.negative?
      pago_iva = (i.amount.to_f * (1 + tax / 100.0)).round(2)
      exen_iva = (exencion.to_f * (1 + tax / 100.0)).round(2)
      total_row = (pago_iva + exen_iva).round(2)
      format('%4d  %-12s %16s %16s %16s %16s',
             i.number, fdate(i.due_date), "$#{money(pago_iva)}",
             exencion ? "$#{money(exen_iva)}" : '$0.00',
             "$#{money(total_row)}", "$#{money(saldo)}")
    end
    rate = @c.respond_to?(:interest_rate) ? @c.interest_rate : 25.0
    factor = @c.respond_to?(:finance_factor) ? @c.finance_factor : 1.25
    note = format("\nCargo financiero: %g%% sobre el principal (diferencia a 100 del factor de financiamiento %.2f). Interés: $%s sobre un principal de $%s.",
                  rate, factor, money(@c.respond_to?(:interest_amount) ? @c.interest_amount : 0),
                  money(@c.respond_to?(:principal_amount) ? @c.principal_amount : 0))
    if @c.respond_to?(:annual_interest_rate) && @c.annual_interest_rate.positive?
      note += format("\nTasa de interés ordinaria ANUAL equivalente por el plazo contratado: %g%%.", @c.annual_interest_rate)
    end
    if @c.respond_to?(:computed_cat) && @c.computed_cat.positive?
      note += format("\nCAT: %g%% efectivo anual. Para fines informativos y de comparación. Incluye la cuota de procesamiento; no incluye el seguro opcional (exención de responsabilidad) ni IVA.", @c.computed_cat)
    end
    note += format("\nIVA aplicado a cada pago: %g%%.", tax) if tax.positive?
    mora = Product.respond_to?(:mora_rate) ? Product.mora_rate : 0.0
    note += format("\nInterés moratorio anual sobre pagos vencidos (a partir del 2o día de atraso): %g%% (tasa/360 por día).", mora) if mora.positive?
    ([header] + lines).join("\n") + note
  end
end
