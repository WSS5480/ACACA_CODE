# frozen_string_literal: true

# Re-descarga SOLO las FOTOS de todos los productos por ASIN (Rainforest -> Amazon -> R2).
# NO toca precios, turns, factor ni estatus.
# Requiere: AWS_* (R2) configuradas en el servicio y la API key de Rainforest guardada.
#
#   bin/rails runner script/refresh_photos.rb

svc = RainforestImportService.new
abort 'No hay API key de Rainforest configurada (Configuración).' unless svc.respond_to?(:import_selected)

ok = 0
sin = []
err = []
scope = Product.where.not(asin: [nil, ''])
puts "== Refrescando fotos de #{scope.count} productos =="

scope.find_each do |p|
  data = svc.send(:fetch_product_detail, p.asin, 'amazon.com.mx')
  urls = (data && data['images'] || []).map { |i| i['link'] }.compact
  if urls.blank?
    sin << p.asin
    puts "  ⚠ #{p.asin}: sin fotos en Rainforest"
    next
  end
  ManageJson::DownloadProductImagesJob.new.perform(p.id, urls)
  n = p.reload.images.attached? ? p.images.count : 0
  ok += 1
  puts "  ✓ #{p.asin}: #{n} fotos"
rescue StandardError => e
  err << p.asin
  puts "  ✗ #{p.asin}: #{e.message}"
end

puts ''
puts "== RESUMEN: #{ok} con fotos nuevas · #{sin.size} sin fotos · #{err.size} errores =="
puts "Sin fotos: #{sin.join(', ')}" if sin.any?
puts "Errores: #{err.join(', ')}" if err.any?
svc_name = ActiveStorage::Blob.order(:id).last&.service_name
puts "Servicio de almacenamiento de la última foto: #{svc_name} (debe decir 'amazon' = R2)"
