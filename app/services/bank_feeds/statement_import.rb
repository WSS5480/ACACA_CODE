# frozen_string_literal: true

require 'csv'
require 'digest'

module BankFeeds
  # IMPORTACIÓN de un estado de cuenta (CSV exportado del portal del banco) a una
  # cuenta MANUAL. Sirve para cualquier banco — hoy es el camino para México.
  #   mapping: índices de columna (0-based) → { date:, description:, amount: | debit: + credit:, balance: }
  #   options: { header: true, date_format: 'auto'|'dmy'|'mdy'|'ymd', negate: false, closing_balance: nil }
  # Idempotente: cada renglón recibe una huella (fecha + importe + descripción +
  # ordinal dentro del archivo); re-importar el mismo archivo no duplica nada.
  class StatementImport
    Result = Struct.new(:imported, :duplicates, :skipped, :errors, :first_on, :last_on, :closing_balance, keyword_init: true)

    DATE_FORMATS = {
      'ymd' => ['%Y-%m-%d', '%Y/%m/%d', '%Y%m%d', '%Y-%m-%d %H:%M:%S', '%Y-%m-%dT%H:%M:%S'],
      'dmy' => ['%d/%m/%Y', '%d-%m-%Y', '%d.%m.%Y', '%d/%m/%y', '%d-%m-%y', '%d %b %Y', '%d %B %Y', '%d/%b/%Y', '%d-%b-%Y', '%d-%b-%y'],
      'mdy' => ['%m/%d/%Y', '%m-%d-%Y', '%m/%d/%y', '%m-%d-%y', '%b %d, %Y', '%B %d, %Y', '%b %d %Y']
    }.freeze
    MESES = { 'ene' => 'jan', 'abr' => 'apr', 'ago' => 'aug', 'dic' => 'dec', 'enero' => 'january', 'febrero' => 'february',
              'marzo' => 'march', 'abril' => 'april', 'mayo' => 'may', 'junio' => 'june', 'julio' => 'july', 'agosto' => 'august',
              'septiembre' => 'september', 'setiembre' => 'september', 'octubre' => 'october', 'noviembre' => 'november',
              'diciembre' => 'december' }.freeze

    def self.detect_delimiter(text)
      sample = text.lines.first(5).join
      counts = { ',' => sample.count(','), ';' => sample.count(';'), "\t" => sample.count("\t"), '|' => sample.count('|') }
      counts.max_by { |_, v| v }&.first || ','
    end

    def self.parse_rows(text, delimiter: nil)
      text = text.to_s.dup.force_encoding('UTF-8')
      text = text.encode('UTF-8', 'ISO-8859-1') unless text.valid_encoding?
      text = text.sub(/\A\xEF\xBB\xBF/, '') # BOM
      delimiter ||= detect_delimiter(text)
      CSV.parse(text, col_sep: delimiter, liberal_parsing: true, skip_blanks: true)
    rescue CSV::MalformedCSVError
      text.lines.map { |l| l.chomp.split(delimiter) }
    end

    def self.run!(account:, csv_text:, mapping:, options: {}, actor: nil)
      mapping = (mapping || {}).to_h.transform_keys(&:to_s)
      options = (options || {}).to_h.transform_keys(&:to_s)
      rows = parse_rows(csv_text, delimiter: options['delimiter'].presence)
      rows = rows.drop(1) if options.fetch('header', true) && rows.any?
      date_i = idx(mapping['date'])
      desc_i = idx(mapping['description'])
      amt_i  = idx(mapping['amount'])
      deb_i  = idx(mapping['debit'])
      cre_i  = idx(mapping['credit'])
      bal_i  = idx(mapping['balance'])
      raise 'Falta la columna de fecha' if date_i.nil?
      raise 'Indica la columna de importe (o las de cargo y abono)' if amt_i.nil? && deb_i.nil? && cre_i.nil?

      fmt = options['date_format'].presence || 'auto'
      negate = ActiveModel::Type::Boolean.new.cast(options['negate'])
      parsed = []
      errors = []
      rows.each_with_index do |r, i|
        next if r.nil? || r.compact.all? { |c| c.to_s.strip.empty? }

        date = parse_date(r[date_i], fmt)
        if date.nil?
          errors << "Renglón #{i + 1}: fecha no reconocida «#{r[date_i]}»" if errors.size < 20
          next
        end
        amount = if amt_i
                   v = parse_amount(r[amt_i])
                   v.nil? ? nil : (negate ? -v : v)
                 else
                   d = deb_i ? parse_amount(r[deb_i]) : nil
                   c = cre_i ? parse_amount(r[cre_i]) : nil
                   (d.nil? && c.nil?) ? nil : ((c || 0).abs - (d || 0).abs)
                 end
        if amount.nil? || amount.zero?
          errors << "Renglón #{i + 1}: importe vacío o cero" if amount.nil? && errors.size < 20
          next
        end
        parsed << { date: date, amount: amount.round(2), description: (desc_i ? r[desc_i].to_s.squish : '').truncate(255),
                    balance: (bal_i ? parse_amount(r[bal_i]) : nil), order: i }
      end
      raise 'No se encontró ningún renglón válido con esa configuración de columnas.' if parsed.empty?

      seen = Hash.new(0)
      imported = duplicates = 0
      currency = account.currency.presence || 'MXN'
      BankTransaction.transaction do
        parsed.each do |p|
          key = [p[:date].to_s, format('%.2f', p[:amount]), p[:description].downcase]
          seen[key] += 1
          fingerprint = Digest::SHA1.hexdigest((key + [seen[key]]).join('|'))[0, 32]
          if BankTransaction.exists?(bank_account_id: account.id, external_id: "stmt-#{fingerprint}")
            duplicates += 1
            next
          end
          BankTransaction.create!(
            bank_account: account, external_id: "stmt-#{fingerprint}", posted_on: p[:date], amount: p[:amount], currency: currency,
            description: p[:description].presence || (p[:amount].positive? ? 'Depósito' : 'Cargo'),
            pending: false, channel: 'statement',
            raw: { 'source' => 'statement_import', 'imported_at' => Time.current.iso8601, 'row' => p[:order] + 1, 'balance' => p[:balance] }
          )
          imported += 1
        end
      end

      closing = options['closing_balance'].presence && parse_amount(options['closing_balance'])
      if closing.nil? && bal_i
        last = parsed.reject { |p| p[:balance].nil? }.max_by { |p| [p[:date], p[:order]] }
        closing = last && last[:balance]
      end
      if closing
        account.update!(current_balance: closing, available_balance: closing, balance_as_of: Time.current)
      end
      conn = account.bank_connection
      conn.update_columns(last_synced_at: Time.current, status: 'active', last_error: nil, updated_at: Time.current)
      AuditLog.record!(actor: actor, action: 'bank_statement_imported', target: account,
                       label: "#{conn.label} · #{account.label}",
                       details: "#{imported} movimientos nuevos, #{duplicates} repetidos · #{parsed.map { |p| p[:date] }.min} → #{parsed.map { |p| p[:date] }.max}") if defined?(AuditLog)
      Result.new(imported: imported, duplicates: duplicates, skipped: rows.size - parsed.size, errors: errors,
                 first_on: parsed.map { |p| p[:date] }.min, last_on: parsed.map { |p| p[:date] }.max, closing_balance: closing)
    end

    def self.idx(v)
      return nil if v.nil? || v.to_s.strip == ''

      Integer(v.to_s, 10)
    rescue ArgumentError
      nil
    end

    def self.parse_date(raw, fmt)
      s = raw.to_s.strip
      return nil if s.empty?

      low = s.downcase
      MESES.each { |es, en| low = low.gsub(/\b#{es}\b/, en) }
      orders = fmt == 'auto' ? %w[ymd dmy mdy] : [fmt]
      orders.each do |o|
        DATE_FORMATS.fetch(o, []).each do |f|
          d = strict_strptime(low, f)
          return d if d
        end
      end
      begin
        d = Date.parse(low)
        d.year.between?(1990, 2100) ? d : nil
      rescue ArgumentError
        nil
      end
    end

    # Date.strptime es permisivo ("10/09/2026" con %Y/%m/%d da el año 10 y sobra "26");
    # aquí se exige que el formato consuma TODO el texto y que el año sea creíble.
    def self.strict_strptime(str, fmt)
      h = Date._strptime(str, fmt)
      return nil if h.nil? || h[:leftover].to_s.strip != '' || h[:year].nil? || h[:mon].nil? || h[:mday].nil?
      return nil unless h[:year].between?(1990, 2100)

      Date.new(h[:year], h[:mon], h[:mday])
    rescue ArgumentError, TypeError
      nil
    end

    # "$1,234.56" → 1234.56 · "(12.00)" → -12.0 · "1.234,56" → 1234.56 · "12,50" → 12.5 · "-$40" → -40
    def self.parse_amount(raw)
      s = raw.to_s.strip
      return nil if s.empty?

      neg = s.include?('(') || s.include?('-')
      s = s.gsub(/[^\d,.]/, '')
      return nil if s.empty? || s !~ /\d/
      if s.include?(',') && s.include?('.')
        if s.rindex(',') > s.rindex('.') then s = s.delete('.').tr(',', '.') else s = s.delete(',') end
      elsif s.include?(',')
        parts = s.split(',')
        s = (parts.size == 2 && parts.last.size <= 2) ? s.tr(',', '.') : s.delete(',')
      end
      v = Float(s)
      neg ? -v : v
    rescue ArgumentError
      nil
    end
  end
end
