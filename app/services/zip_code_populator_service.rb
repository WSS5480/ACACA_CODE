# frozen_string_literal: true

class ZipCodePopulatorService
  attr_reader :country, :clear_existing, :results

  def initialize(country: 'all', clear_existing: false)
    @country = country.to_s.upcase
    @clear_existing = clear_existing
    @results = {}
  end

  def call
    validate_country!

    ActiveRecord::Base.transaction do
      clear_existing_records if clear_existing
      populate_countries
    end

    { success: true, results: results }
  rescue StandardError => e
    { success: false, error: e.message }
  end

  private

  def validate_country!
    raise ArgumentError, "País inválido. Use 'MX', 'US', o 'all'" unless valid_country?
  end

  def valid_country?
    %w[MX US ALL].include?(country)
  end

  def clear_existing_records
    case country
    when 'MX'
      ZipCode.where(country: 'MX').delete_all
    when 'US'
      ZipCode.where(country: 'US').delete_all
    when 'ALL'
      ZipCode.delete_all
    end
  end

  def populate_countries
    results[:mexico] = populate_mexico if %w[MX ALL].include?(country)
    results[:usa] = populate_usa if %w[US ALL].include?(country)
  end

  def populate_mexico
    # File obtained from https://www.correosdemexico.gob.mx/sslservicios/consultacp/CodigoPostal_Exportar.aspx (TXT format)
    file_path = Rails.root.join('mex_zip_codes.txt')
    return { error: 'Archivo mex_zip_codes.txt no encontrado' } unless File.exist?(file_path)

    # Hash to group records by zip code
    grouped_records = {}

    File.readlines(file_path, encoding: 'Windows-1252:UTF-8').each_with_index do |line, index|
      next if index < 2 # Skip disclaimer and header

      columns = line.strip.split('|')
      next if columns.length < 8

      code = columns[0]
      inegi_code = columns[7]
      state_data = MX_STATES_BY_INEGI[inegi_code]

      if grouped_records[code]
        # Add unique values to existing record
        add_unique_value(grouped_records[code], :city, columns[5])
        add_unique_value(grouped_records[code], :municipality, columns[3])
        add_unique_value(grouped_records[code], :settlement, columns[1])
      else
        # Create new record
        grouped_records[code] = {
          code: code,
          country: 'MX',
          state_initials: state_data&.dig(:initials) || inegi_code,
          state_name: state_data&.dig(:name) || columns[4],
          city: columns[5],
          municipality: columns[3],
          settlement: columns[1]
        }
      end
    end

    # Insert consolidated records in batches
    insert_grouped_records(grouped_records)

    { inserted: ZipCode.where(country: 'MX').count }
  end

  def populate_usa
    # File obtained from https://github.com/pseudosavant/usps-zip-codes/tree/main (JSON in path dist/ZIPCodes.json)
    file_path = Rails.root.join('usa_zip_codes.json')
    return { error: 'Archivo usa_zip_codes.json no encontrado' } unless File.exist?(file_path)

    json_data = JSON.parse(File.read(file_path))

    # Hash to group records by zip code
    grouped_records = {}

    json_data.each do |zip_code, data|
      state_abbr = data['state']
      state_data = US_STATES_BY_ABBR[state_abbr]
      city = data['city']&.titleize

      if grouped_records[zip_code]
        # Add unique values to existing record
        add_unique_value(grouped_records[zip_code], :city, city)
      else
        # Create new record
        grouped_records[zip_code] = {
          code: zip_code,
          country: 'US',
          state_initials: state_abbr,
          state_name: state_data || state_abbr,
          city: city,
          municipality: nil,
          settlement: nil
        }
      end
    end

    # Insert consolidated records in batches
    insert_grouped_records(grouped_records)

    { inserted: ZipCode.where(country: 'US').count }
  end

  def add_unique_value(record, field, value)
    return if value.blank?

    current_value = record[field]
    return if current_value.blank? && record[field] = value

    # Split current values and check if the new value already exists
    existing_values = current_value.to_s.split(', ').map(&:strip)
    return if existing_values.include?(value.strip)

    # Append the new unique value
    record[field] = "#{current_value}, #{value}"
  end

  def insert_grouped_records(grouped_records)
    current_time = Time.current
    records = []

    grouped_records.each_value do |record|
      record[:created_at] = current_time
      record[:updated_at] = current_time
      records << record

      if records.size >= BATCH_SIZE
        ZipCode.insert_all(records)
        records = []
      end
    end

    ZipCode.insert_all(records) if records.any?
  end

  BATCH_SIZE = 5000

  # Mapeo de códigos INEGI a abreviaturas del frontend para México
  # El archivo mex_zip_codes.txt usa códigos INEGI (01, 02, etc.)
  MX_STATES_BY_INEGI = {
    '01' => { initials: 'AGS', name: 'Aguascalientes' },
    '02' => { initials: 'BC', name: 'Baja California' },
    '03' => { initials: 'BCS', name: 'Baja California Sur' },
    '04' => { initials: 'CAM', name: 'Campeche' },
    '05' => { initials: 'COAH', name: 'Coahuila' },
    '06' => { initials: 'COL', name: 'Colima' },
    '07' => { initials: 'CHIS', name: 'Chiapas' },
    '08' => { initials: 'CHIH', name: 'Chihuahua' },
    '09' => { initials: 'CDMX', name: 'Ciudad de México' },
    '10' => { initials: 'DGO', name: 'Durango' },
    '11' => { initials: 'GTO', name: 'Guanajuato' },
    '12' => { initials: 'GRO', name: 'Guerrero' },
    '13' => { initials: 'HGO', name: 'Hidalgo' },
    '14' => { initials: 'JAL', name: 'Jalisco' },
    '15' => { initials: 'MEX', name: 'Estado de México' },
    '16' => { initials: 'MICH', name: 'Michoacán' },
    '17' => { initials: 'MOR', name: 'Morelos' },
    '18' => { initials: 'NAY', name: 'Nayarit' },
    '19' => { initials: 'NL', name: 'Nuevo León' },
    '20' => { initials: 'OAX', name: 'Oaxaca' },
    '21' => { initials: 'PUE', name: 'Puebla' },
    '22' => { initials: 'QRO', name: 'Querétaro' },
    '23' => { initials: 'QROO', name: 'Quintana Roo' },
    '24' => { initials: 'SLP', name: 'San Luis Potosí' },
    '25' => { initials: 'SIN', name: 'Sinaloa' },
    '26' => { initials: 'SON', name: 'Sonora' },
    '27' => { initials: 'TAB', name: 'Tabasco' },
    '28' => { initials: 'TAMPS', name: 'Tamaulipas' },
    '29' => { initials: 'TLAX', name: 'Tlaxcala' },
    '30' => { initials: 'VER', name: 'Veracruz' },
    '31' => { initials: 'YUC', name: 'Yucatán' },
    '32' => { initials: 'ZAC', name: 'Zacatecas' }
  }.freeze

  # Mapeo de abreviaturas a nombres completos para USA (coincide con el frontend)
  US_STATES_BY_ABBR = {
    'AL' => 'Alabama',
    'AK' => 'Alaska',
    'AZ' => 'Arizona',
    'AR' => 'Arkansas',
    'CA' => 'California',
    'CO' => 'Colorado',
    'CT' => 'Connecticut',
    'DE' => 'Delaware',
    'FL' => 'Florida',
    'GA' => 'Georgia',
    'HI' => 'Hawaii',
    'ID' => 'Idaho',
    'IL' => 'Illinois',
    'IN' => 'Indiana',
    'IA' => 'Iowa',
    'KS' => 'Kansas',
    'KY' => 'Kentucky',
    'LA' => 'Louisiana',
    'ME' => 'Maine',
    'MD' => 'Maryland',
    'MA' => 'Massachusetts',
    'MI' => 'Michigan',
    'MN' => 'Minnesota',
    'MS' => 'Mississippi',
    'MO' => 'Missouri',
    'MT' => 'Montana',
    'NE' => 'Nebraska',
    'NV' => 'Nevada',
    'NH' => 'New Hampshire',
    'NJ' => 'New Jersey',
    'NM' => 'New Mexico',
    'NY' => 'New York',
    'NC' => 'North Carolina',
    'ND' => 'North Dakota',
    'OH' => 'Ohio',
    'OK' => 'Oklahoma',
    'OR' => 'Oregon',
    'PA' => 'Pennsylvania',
    'RI' => 'Rhode Island',
    'SC' => 'South Carolina',
    'SD' => 'South Dakota',
    'TN' => 'Tennessee',
    'TX' => 'Texas',
    'UT' => 'Utah',
    'VT' => 'Vermont',
    'VA' => 'Virginia',
    'WA' => 'Washington',
    'DC' => 'Washington D.C.',
    'WV' => 'West Virginia',
    'WI' => 'Wisconsin',
    'WY' => 'Wyoming',
    # Territorios de USA (no están en el frontend pero existen en el archivo JSON)
    'PR' => 'Puerto Rico',
    'VI' => 'Virgin Islands',
    'GU' => 'Guam',
    'AS' => 'American Samoa',
    'MP' => 'Northern Mariana Islands'
  }.freeze
end
