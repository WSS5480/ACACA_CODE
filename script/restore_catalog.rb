# frozen_string_literal: true

# Restauración del catálogo tras la pérdida de la base de datos (2026-08-04).
# Corre DESPUÉS de: bin/rails db:migrate && bin/rails db:seed
# y de guardar la API key de Rainforest en Configuración (admin).
#
#   bin/rails runner script/restore_catalog.rb
#
# Restaura desde _backup/acasa-backup-1785875851234.json:
#   1. Categorías (nombre, external_id, link)
#   2. Tipos de cambio
#   3. Versiones del motor de riesgo (mejor esfuerzo)
#   4. Productos: re-importa por ASIN vía Rainforest (imágenes frescas de Amazon)
#      y luego aplica los precios/estatus/turns guardados del respaldo.

require 'json'

path = Rails.root.join('_backup', 'acasa-backup-1785875851234.json')
abort "No existe #{path}" unless File.exist?(path)
data = JSON.parse(File.read(path))

puts "== Respaldo del #{data['exported_at']} =="

# ---------- 1. Categorías ----------
cats = (data.dig('categories', 'data') || [])
created = 0
cats.each do |c|
  a = c['attributes'] || {}
  next if a['external_id'].blank? && a['name'].blank?
  cat = Category.find_or_initialize_by(external_id: a['external_id'])
  cat.name = a['name']
  cat.original_link = a['original_link'] if cat.respond_to?(:original_link=)
  created += 1 if cat.new_record?
  cat.save!
rescue StandardError => e
  puts "  ⚠ categoría #{a['name']}: #{e.message}"
end
puts "✅ Categorías: #{Category.count} (#{created} nuevas)"

# ---------- 2. Tipos de cambio ----------
fx = (data.dig('exchange_rates', 'data') || [])
fx.reverse_each do |r|
  a = r['attributes'] || {}
  attrs = a.slice(*ExchangeRate.column_names).except('id')
  next if attrs.blank?
  ExchangeRate.create!(attrs)
rescue StandardError => e
  puts "  ⚠ tipo de cambio: #{e.message}"
end
puts "✅ Tipos de cambio: #{ExchangeRate.count}"

# ---------- 3. Motor de riesgo (mejor esfuerzo) ----------
begin
  rk = data['risk_versions'] || {}
  versions = rk['versions'] || []
  if defined?(RiskEngineConfig) && versions.any?
    versions.each do |v|
      attrs = v.slice(*RiskEngineConfig.column_names).except('id')
      next if attrs.blank?
      cfg = RiskEngineConfig.find_or_initialize_by(version: v['version'])
      cfg.assign_attributes(attrs)
      cfg.save!
    end
    if rk['active_version'].present?
      RiskEngineConfig.where.not(version: rk['active_version']).update_all(active: false) if RiskEngineConfig.column_names.include?('active')
      act = RiskEngineConfig.find_by(version: rk['active_version'])
      act.update!(active: true) if act && act.respond_to?(:active=)
    end
    puts "✅ Motor de riesgo: #{RiskEngineConfig.count} versiones (activa: #{rk['active_version']})"
  else
    puts "ℹ Motor de riesgo: sin datos que restaurar (usa la versión por defecto)"
  end
rescue StandardError => e
  puts "⚠ Motor de riesgo no restaurado (#{e.message}) — recrea las reglas en el admin si hace falta"
end

# ---------- 4. Productos ----------
prods = (data.dig('products', 'data') || [])
by_asin = {}
prods.each do |p|
  a = p['attributes'] || {}
  by_asin[a['asin']] = a if a['asin'].present?
end
puts "== Importando #{by_asin.size} productos por ASIN vía Rainforest (imágenes desde Amazon) =="

svc = RainforestImportService.new
result = svc.import_selected(asins: by_asin.keys, amazon_domain: 'amazon.com.mx')
puts "Rainforest: #{result.inspect[0, 300]}"

# Aplicar precios/estatus del respaldo sobre lo importado
overlaid = 0
missing = []
by_asin.each do |asin, a|
  prod = Product.find_by(asin: asin)
  if prod.nil?
    missing << asin
    next
  end
  updates = {}
  %w[price price_with_discount original_price turns decimal_factor status keywords].each do |f|
    updates[f] = a[f] if a.key?(f) && !a[f].nil? && prod.respond_to?("#{f}=")
  end
  prod.update_columns(updates) if updates.any?
  overlaid += 1
rescue StandardError => e
  puts "  ⚠ overlay #{asin}: #{e.message}"
end
puts "✅ Productos con precios restaurados: #{overlaid}"
puts "⚠ ASINs que Rainforest no importó (reintenta desde Catálogos): #{missing.join(', ')}" if missing.any?

puts ""
puts "== RESUMEN =="
puts "Productos: #{Product.count} (activos: #{Product.where(status: 'active').count rescue '?'})"
puts "Categorías: #{Category.count} | FX: #{ExchangeRate.count} | Usuarios: #{User.count}"
puts "Pendiente manual: recrear cuentas admin reales en Seguridad (con enlace de contraseña por correo),"
puts "volver a fijar líneas de crédito de prueba, y cambiar la contraseña de admin@test.com."
