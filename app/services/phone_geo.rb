# frozen_string_literal: true

# PAÍSES y TELÉFONOS para compradores en cualquier país. Misma tabla que
# www-acasa-main/utils/countries.js (generadas juntas): lada → país → zona horaria
# y longitud nacional típica del número (para PhoneCheck). Sin gemas.
module PhoneGeo
  # iso => [nombre ES, nombre EN, lada, zona horaria representativa]
  COUNTRIES = {
    'AF' => ['Afganistán', 'Afghanistan', '+93', 'Asia/Kabul'],
    'AL' => ['Albania', 'Albania', '+355', 'Europe/Tirane'],
    'DE' => ['Alemania', 'Germany', '+49', 'Europe/Berlin'],
    'AD' => ['Andorra', 'Andorra', '+376', 'Europe/Andorra'],
    'AO' => ['Angola', 'Angola', '+244', 'Africa/Luanda'],
    'AG' => ['Antigua y Barbuda', 'Antigua and Barbuda', '+1', 'America/Antigua'],
    'SA' => ['Arabia Saudita', 'Saudi Arabia', '+966', 'Asia/Riyadh'],
    'DZ' => ['Argelia', 'Algeria', '+213', 'Africa/Algiers'],
    'AR' => ['Argentina', 'Argentina', '+54', 'America/Argentina/Buenos_Aires'],
    'AM' => ['Armenia', 'Armenia', '+374', 'Asia/Yerevan'],
    'AU' => ['Australia', 'Australia', '+61', 'Australia/Sydney'],
    'AT' => ['Austria', 'Austria', '+43', 'Europe/Vienna'],
    'AZ' => ['Azerbaiyán', 'Azerbaijan', '+994', 'Asia/Baku'],
    'BS' => ['Bahamas', 'Bahamas', '+1', 'America/Nassau'],
    'BD' => ['Bangladés', 'Bangladesh', '+880', 'Asia/Dhaka'],
    'BB' => ['Barbados', 'Barbados', '+1', 'America/Barbados'],
    'BH' => ['Baréin', 'Bahrain', '+973', 'Asia/Bahrain'],
    'BE' => ['Bélgica', 'Belgium', '+32', 'Europe/Brussels'],
    'BZ' => ['Belice', 'Belize', '+501', 'America/Belize'],
    'BJ' => ['Benín', 'Benin', '+229', 'Africa/Porto-Novo'],
    'BY' => ['Bielorrusia', 'Belarus', '+375', 'Europe/Minsk'],
    'BO' => ['Bolivia', 'Bolivia', '+591', 'America/La_Paz'],
    'BA' => ['Bosnia y Herzegovina', 'Bosnia and Herzegovina', '+387', 'Europe/Sarajevo'],
    'BW' => ['Botsuana', 'Botswana', '+267', 'Africa/Gaborone'],
    'BR' => ['Brasil', 'Brazil', '+55', 'America/Sao_Paulo'],
    'BN' => ['Brunéi', 'Brunei', '+673', 'Asia/Brunei'],
    'BG' => ['Bulgaria', 'Bulgaria', '+359', 'Europe/Sofia'],
    'BF' => ['Burkina Faso', 'Burkina Faso', '+226', 'Africa/Ouagadougou'],
    'BI' => ['Burundi', 'Burundi', '+257', 'Africa/Bujumbura'],
    'BT' => ['Bután', 'Bhutan', '+975', 'Asia/Thimphu'],
    'CV' => ['Cabo Verde', 'Cape Verde', '+238', 'Atlantic/Cape_Verde'],
    'KH' => ['Camboya', 'Cambodia', '+855', 'Asia/Phnom_Penh'],
    'CM' => ['Camerún', 'Cameroon', '+237', 'Africa/Douala'],
    'CA' => ['Canadá', 'Canada', '+1', 'America/Toronto'],
    'QA' => ['Catar', 'Qatar', '+974', 'Asia/Qatar'],
    'TD' => ['Chad', 'Chad', '+235', 'Africa/Ndjamena'],
    'CL' => ['Chile', 'Chile', '+56', 'America/Santiago'],
    'CN' => ['China', 'China', '+86', 'Asia/Shanghai'],
    'CY' => ['Chipre', 'Cyprus', '+357', 'Asia/Nicosia'],
    'CO' => ['Colombia', 'Colombia', '+57', 'America/Bogota'],
    'KM' => ['Comoras', 'Comoros', '+269', 'Indian/Comoro'],
    'CG' => ['Congo', 'Congo', '+242', 'Africa/Brazzaville'],
    'CD' => ['Congo (Rep. Dem.)', 'Congo (DRC)', '+243', 'Africa/Kinshasa'],
    'KR' => ['Corea del Sur', 'South Korea', '+82', 'Asia/Seoul'],
    'CR' => ['Costa Rica', 'Costa Rica', '+506', 'America/Costa_Rica'],
    'CI' => ['Costa de Marfil', 'Ivory Coast', '+225', 'Africa/Abidjan'],
    'HR' => ['Croacia', 'Croatia', '+385', 'Europe/Zagreb'],
    'DK' => ['Dinamarca', 'Denmark', '+45', 'Europe/Copenhagen'],
    'DM' => ['Dominica', 'Dominica', '+1', 'America/Dominica'],
    'EC' => ['Ecuador', 'Ecuador', '+593', 'America/Guayaquil'],
    'EG' => ['Egipto', 'Egypt', '+20', 'Africa/Cairo'],
    'SV' => ['El Salvador', 'El Salvador', '+503', 'America/El_Salvador'],
    'AE' => ['Emiratos Árabes Unidos', 'United Arab Emirates', '+971', 'Asia/Dubai'],
    'ER' => ['Eritrea', 'Eritrea', '+291', 'Africa/Asmara'],
    'SK' => ['Eslovaquia', 'Slovakia', '+421', 'Europe/Bratislava'],
    'SI' => ['Eslovenia', 'Slovenia', '+386', 'Europe/Ljubljana'],
    'ES' => ['España', 'Spain', '+34', 'Europe/Madrid'],
    'US' => ['Estados Unidos', 'United States', '+1', 'America/New_York'],
    'EE' => ['Estonia', 'Estonia', '+372', 'Europe/Tallinn'],
    'SZ' => ['Esuatini', 'Eswatini', '+268', 'Africa/Mbabane'],
    'ET' => ['Etiopía', 'Ethiopia', '+251', 'Africa/Addis_Ababa'],
    'PH' => ['Filipinas', 'Philippines', '+63', 'Asia/Manila'],
    'FI' => ['Finlandia', 'Finland', '+358', 'Europe/Helsinki'],
    'FJ' => ['Fiyi', 'Fiji', '+679', 'Pacific/Fiji'],
    'FR' => ['Francia', 'France', '+33', 'Europe/Paris'],
    'GA' => ['Gabón', 'Gabon', '+241', 'Africa/Libreville'],
    'GM' => ['Gambia', 'Gambia', '+220', 'Africa/Banjul'],
    'GE' => ['Georgia', 'Georgia', '+995', 'Asia/Tbilisi'],
    'GH' => ['Ghana', 'Ghana', '+233', 'Africa/Accra'],
    'GD' => ['Granada', 'Grenada', '+1', 'America/Grenada'],
    'GR' => ['Grecia', 'Greece', '+30', 'Europe/Athens'],
    'GT' => ['Guatemala', 'Guatemala', '+502', 'America/Guatemala'],
    'GN' => ['Guinea', 'Guinea', '+224', 'Africa/Conakry'],
    'GQ' => ['Guinea Ecuatorial', 'Equatorial Guinea', '+240', 'Africa/Malabo'],
    'GW' => ['Guinea-Bisáu', 'Guinea-Bissau', '+245', 'Africa/Bissau'],
    'GY' => ['Guyana', 'Guyana', '+592', 'America/Guyana'],
    'HT' => ['Haití', 'Haiti', '+509', 'America/Port-au-Prince'],
    'HN' => ['Honduras', 'Honduras', '+504', 'America/Tegucigalpa'],
    'HU' => ['Hungría', 'Hungary', '+36', 'Europe/Budapest'],
    'IN' => ['India', 'India', '+91', 'Asia/Kolkata'],
    'ID' => ['Indonesia', 'Indonesia', '+62', 'Asia/Jakarta'],
    'IQ' => ['Irak', 'Iraq', '+964', 'Asia/Baghdad'],
    'IE' => ['Irlanda', 'Ireland', '+353', 'Europe/Dublin'],
    'IS' => ['Islandia', 'Iceland', '+354', 'Atlantic/Reykjavik'],
    'IL' => ['Israel', 'Israel', '+972', 'Asia/Jerusalem'],
    'IT' => ['Italia', 'Italy', '+39', 'Europe/Rome'],
    'JM' => ['Jamaica', 'Jamaica', '+1', 'America/Jamaica'],
    'JP' => ['Japón', 'Japan', '+81', 'Asia/Tokyo'],
    'JO' => ['Jordania', 'Jordan', '+962', 'Asia/Amman'],
    'KZ' => ['Kazajistán', 'Kazakhstan', '+7', 'Asia/Almaty'],
    'KE' => ['Kenia', 'Kenya', '+254', 'Africa/Nairobi'],
    'KG' => ['Kirguistán', 'Kyrgyzstan', '+996', 'Asia/Bishkek'],
    'KI' => ['Kiribati', 'Kiribati', '+686', 'Pacific/Tarawa'],
    'KW' => ['Kuwait', 'Kuwait', '+965', 'Asia/Kuwait'],
    'LA' => ['Laos', 'Laos', '+856', 'Asia/Vientiane'],
    'LS' => ['Lesoto', 'Lesotho', '+266', 'Africa/Maseru'],
    'LV' => ['Letonia', 'Latvia', '+371', 'Europe/Riga'],
    'LB' => ['Líbano', 'Lebanon', '+961', 'Asia/Beirut'],
    'LR' => ['Liberia', 'Liberia', '+231', 'Africa/Monrovia'],
    'LY' => ['Libia', 'Libya', '+218', 'Africa/Tripoli'],
    'LI' => ['Liechtenstein', 'Liechtenstein', '+423', 'Europe/Vaduz'],
    'LT' => ['Lituania', 'Lithuania', '+370', 'Europe/Vilnius'],
    'LU' => ['Luxemburgo', 'Luxembourg', '+352', 'Europe/Luxembourg'],
    'MK' => ['Macedonia del Norte', 'North Macedonia', '+389', 'Europe/Skopje'],
    'MG' => ['Madagascar', 'Madagascar', '+261', 'Indian/Antananarivo'],
    'MY' => ['Malasia', 'Malaysia', '+60', 'Asia/Kuala_Lumpur'],
    'MW' => ['Malaui', 'Malawi', '+265', 'Africa/Blantyre'],
    'MV' => ['Maldivas', 'Maldives', '+960', 'Indian/Maldives'],
    'ML' => ['Malí', 'Mali', '+223', 'Africa/Bamako'],
    'MT' => ['Malta', 'Malta', '+356', 'Europe/Malta'],
    'MA' => ['Marruecos', 'Morocco', '+212', 'Africa/Casablanca'],
    'MU' => ['Mauricio', 'Mauritius', '+230', 'Indian/Mauritius'],
    'MR' => ['Mauritania', 'Mauritania', '+222', 'Africa/Nouakchott'],
    'MX' => ['México', 'Mexico', '+52', 'America/Mexico_City'],
    'FM' => ['Micronesia', 'Micronesia', '+691', 'Pacific/Pohnpei'],
    'MD' => ['Moldavia', 'Moldova', '+373', 'Europe/Chisinau'],
    'MC' => ['Mónaco', 'Monaco', '+377', 'Europe/Monaco'],
    'MN' => ['Mongolia', 'Mongolia', '+976', 'Asia/Ulaanbaatar'],
    'ME' => ['Montenegro', 'Montenegro', '+382', 'Europe/Podgorica'],
    'MZ' => ['Mozambique', 'Mozambique', '+258', 'Africa/Maputo'],
    'MM' => ['Myanmar', 'Myanmar', '+95', 'Asia/Yangon'],
    'NA' => ['Namibia', 'Namibia', '+264', 'Africa/Windhoek'],
    'NR' => ['Nauru', 'Nauru', '+674', 'Pacific/Nauru'],
    'NP' => ['Nepal', 'Nepal', '+977', 'Asia/Kathmandu'],
    'NI' => ['Nicaragua', 'Nicaragua', '+505', 'America/Managua'],
    'NE' => ['Níger', 'Niger', '+227', 'Africa/Niamey'],
    'NG' => ['Nigeria', 'Nigeria', '+234', 'Africa/Lagos'],
    'NO' => ['Noruega', 'Norway', '+47', 'Europe/Oslo'],
    'NZ' => ['Nueva Zelanda', 'New Zealand', '+64', 'Pacific/Auckland'],
    'OM' => ['Omán', 'Oman', '+968', 'Asia/Muscat'],
    'NL' => ['Países Bajos', 'Netherlands', '+31', 'Europe/Amsterdam'],
    'PK' => ['Pakistán', 'Pakistan', '+92', 'Asia/Karachi'],
    'PW' => ['Palaos', 'Palau', '+680', 'Pacific/Palau'],
    'PA' => ['Panamá', 'Panama', '+507', 'America/Panama'],
    'PG' => ['Papúa Nueva Guinea', 'Papua New Guinea', '+675', 'Pacific/Port_Moresby'],
    'PY' => ['Paraguay', 'Paraguay', '+595', 'America/Asuncion'],
    'PE' => ['Perú', 'Peru', '+51', 'America/Lima'],
    'PL' => ['Polonia', 'Poland', '+48', 'Europe/Warsaw'],
    'PT' => ['Portugal', 'Portugal', '+351', 'Europe/Lisbon'],
    'PR' => ['Puerto Rico', 'Puerto Rico', '+1', 'America/Puerto_Rico'],
    'GB' => ['Reino Unido', 'United Kingdom', '+44', 'Europe/London'],
    'CF' => ['República Centroafricana', 'Central African Republic', '+236', 'Africa/Bangui'],
    'CZ' => ['República Checa', 'Czech Republic', '+420', 'Europe/Prague'],
    'DO' => ['República Dominicana', 'Dominican Republic', '+1', 'America/Santo_Domingo'],
    'RW' => ['Ruanda', 'Rwanda', '+250', 'Africa/Kigali'],
    'RO' => ['Rumania', 'Romania', '+40', 'Europe/Bucharest'],
    'RU' => ['Rusia', 'Russia', '+7', 'Europe/Moscow'],
    'WS' => ['Samoa', 'Samoa', '+685', 'Pacific/Apia'],
    'KN' => ['San Cristóbal y Nieves', 'Saint Kitts and Nevis', '+1', 'America/St_Kitts'],
    'SM' => ['San Marino', 'San Marino', '+378', 'Europe/San_Marino'],
    'VC' => ['San Vicente y las Granadinas', 'Saint Vincent and the Grenadines', '+1', 'America/St_Vincent'],
    'LC' => ['Santa Lucía', 'Saint Lucia', '+1', 'America/St_Lucia'],
    'ST' => ['Santo Tomé y Príncipe', 'Sao Tome and Principe', '+239', 'Africa/Sao_Tome'],
    'SN' => ['Senegal', 'Senegal', '+221', 'Africa/Dakar'],
    'RS' => ['Serbia', 'Serbia', '+381', 'Europe/Belgrade'],
    'SC' => ['Seychelles', 'Seychelles', '+248', 'Indian/Mahe'],
    'SL' => ['Sierra Leona', 'Sierra Leone', '+232', 'Africa/Freetown'],
    'SG' => ['Singapur', 'Singapore', '+65', 'Asia/Singapore'],
    'LK' => ['Sri Lanka', 'Sri Lanka', '+94', 'Asia/Colombo'],
    'ZA' => ['Sudáfrica', 'South Africa', '+27', 'Africa/Johannesburg'],
    'SD' => ['Sudán', 'Sudan', '+249', 'Africa/Khartoum'],
    'SS' => ['Sudán del Sur', 'South Sudan', '+211', 'Africa/Juba'],
    'SE' => ['Suecia', 'Sweden', '+46', 'Europe/Stockholm'],
    'CH' => ['Suiza', 'Switzerland', '+41', 'Europe/Zurich'],
    'SR' => ['Surinam', 'Suriname', '+597', 'America/Paramaribo'],
    'TH' => ['Tailandia', 'Thailand', '+66', 'Asia/Bangkok'],
    'TW' => ['Taiwán', 'Taiwan', '+886', 'Asia/Taipei'],
    'TZ' => ['Tanzania', 'Tanzania', '+255', 'Africa/Dar_es_Salaam'],
    'TJ' => ['Tayikistán', 'Tajikistan', '+992', 'Asia/Dushanbe'],
    'TL' => ['Timor Oriental', 'Timor-Leste', '+670', 'Asia/Dili'],
    'TG' => ['Togo', 'Togo', '+228', 'Africa/Lome'],
    'TO' => ['Tonga', 'Tonga', '+676', 'Pacific/Tongatapu'],
    'TT' => ['Trinidad y Tobago', 'Trinidad and Tobago', '+1', 'America/Port_of_Spain'],
    'TN' => ['Túnez', 'Tunisia', '+216', 'Africa/Tunis'],
    'TM' => ['Turkmenistán', 'Turkmenistan', '+993', 'Asia/Ashgabat'],
    'TR' => ['Turquía', 'Turkey', '+90', 'Europe/Istanbul'],
    'TV' => ['Tuvalu', 'Tuvalu', '+688', 'Pacific/Funafuti'],
    'UA' => ['Ucrania', 'Ukraine', '+380', 'Europe/Kyiv'],
    'UG' => ['Uganda', 'Uganda', '+256', 'Africa/Kampala'],
    'UY' => ['Uruguay', 'Uruguay', '+598', 'America/Montevideo'],
    'UZ' => ['Uzbekistán', 'Uzbekistan', '+998', 'Asia/Tashkent'],
    'VU' => ['Vanuatu', 'Vanuatu', '+678', 'Pacific/Efate'],
    'VE' => ['Venezuela', 'Venezuela', '+58', 'America/Caracas'],
    'VN' => ['Vietnam', 'Vietnam', '+84', 'Asia/Ho_Chi_Minh'],
    'YE' => ['Yemen', 'Yemen', '+967', 'Asia/Aden'],
    'DJ' => ['Yibuti', 'Djibouti', '+253', 'Africa/Djibouti'],
    'ZM' => ['Zambia', 'Zambia', '+260', 'Africa/Lusaka'],
    'ZW' => ['Zimbabue', 'Zimbabwe', '+263', 'Africa/Harare'],
    'HK' => ['Hong Kong', 'Hong Kong', '+852', 'Asia/Hong_Kong'],
    'GI' => ['Gibraltar', 'Gibraltar', '+350', 'Europe/Gibraltar'],
    'BM' => ['Bermudas', 'Bermuda', '+1', 'Atlantic/Bermuda'],
    'KY' => ['Islas Caimán', 'Cayman Islands', '+1', 'America/Cayman'],
    'AW' => ['Aruba', 'Aruba', '+297', 'America/Aruba'],
    'CW' => ['Curazao', 'Curaçao', '+599', 'America/Curacao'],
    'GU' => ['Guam', 'Guam', '+1', 'Pacific/Guam'],
    'VI' => ['Islas Vírgenes (EE. UU.)', 'U.S. Virgin Islands', '+1', 'America/St_Thomas'],
    'CU' => ['Cuba', 'Cuba', '+53', 'America/Havana'],
    'IR' => ['Irán', 'Iran', '+98', 'Asia/Tehran'],
    'KP' => ['Corea del Norte', 'North Korea', '+850', 'Asia/Pyongyang'],
    'SY' => ['Siria', 'Syria', '+963', 'Asia/Damascus'],
  }.freeze

  # Sanciones integrales de EE. UU. (OFAC) hoy; Configuración → Países puede ampliar la lista.
  DEFAULT_BLOCKED = ['CU', 'IR', 'KP'].freeze

  # Longitud NACIONAL típica [min, max] (dígitos sin lada). Países sin entrada: 6–14.
  NATIONAL_LENGTH = {
    'US' => [10, 10],
    'CA' => [10, 10],
    'PR' => [10, 10],
    'DO' => [10, 10],
    'JM' => [10, 10],
    'MX' => [10, 10],
    'ES' => [9, 9],
    'GB' => [10, 10],
    'DE' => [10, 11],
    'FR' => [9, 9],
    'IT' => [9, 10],
    'PT' => [9, 9],
    'NL' => [9, 9],
    'BE' => [8, 9],
    'CH' => [9, 9],
    'AT' => [10, 13],
    'AR' => [10, 11],
    'BR' => [10, 11],
    'CL' => [9, 9],
    'CO' => [10, 10],
    'PE' => [9, 9],
    'EC' => [9, 9],
    'GT' => [8, 8],
    'HN' => [8, 8],
    'SV' => [8, 8],
    'NI' => [8, 8],
    'CR' => [8, 8],
    'PA' => [8, 8],
    'VE' => [10, 10],
    'BO' => [8, 8],
    'UY' => [8, 8],
    'PY' => [9, 9],
    'AU' => [9, 9],
    'NZ' => [8, 10],
    'JP' => [10, 10],
    'KR' => [9, 10],
    'IN' => [10, 10],
    'CN' => [11, 11],
    'PL' => [9, 9],
    'SE' => [7, 10],
    'NO' => [8, 8],
    'DK' => [8, 8],
    'FI' => [6, 10],
    'IE' => [9, 9],
    'RU' => [10, 10],
    'TR' => [10, 10],
    'IL' => [9, 9],
    'ZA' => [9, 9],
    'AE' => [9, 9],
    'SA' => [9, 9],
    'PH' => [10, 10],
  }.freeze

  # Ladas ordenadas de la más larga a la más corta (para reconocer el país de un número).
  DIALS = COUNTRIES.values.map { |v| v[2] }.uniq.sort_by { |d| -d.length }.freeze
  # País "principal" de cada lada (varias comparten +1: EE. UU. va primero).
  PRIMARY = { '+1' => 'US', '+7' => 'RU' }.freeze

  def self.country(iso)
    COUNTRIES[iso.to_s.upcase]
  end

  def self.name(iso, lang = 'es')
    c = country(iso)
    return '' unless c

    lang.to_s == 'en' ? c[1] : c[0]
  end

  def self.dial_for(iso)
    country(iso)&.dig(2)
  end

  def self.timezone_for_country(iso)
    country(iso)&.dig(3) || 'UTC'
  end

  # Lada y país más probable de un número. Números sin '+' de 10 dígitos se
  # tratan como EE. UU. (convención histórica de la tienda).
  def self.dial_of(raw)
    s = raw.to_s.strip
    digits = s.gsub(/\D/, '')
    return nil if digits.blank?

    plus = s.start_with?('+') || s.start_with?('00') ? "+#{digits.sub(/\A00/, '')}" : nil
    if plus.nil?
      return '+1' if digits.length == 10
      return '+1' if digits.length == 11 && digits.start_with?('1')
      return '+52' if digits.length == 12 && digits.start_with?('52')

      plus = "+#{digits}"
    end
    DIALS.find { |d| plus.start_with?(d) }
  end

  def self.country_of(raw)
    dial = dial_of(raw)
    return nil unless dial
    return PRIMARY[dial] if PRIMARY.key?(dial)

    COUNTRIES.find { |_iso, v| v[2] == dial }&.first
  end

  def self.timezone_of(raw)
    timezone_for_country(country_of(raw))
  end
end
