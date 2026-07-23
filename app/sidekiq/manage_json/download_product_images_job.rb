class ManageJson::DownloadProductImagesJob
  include Sidekiq::Job

  MAX_IMAGES_PER_PRODUCT = 7

  def perform(product_id, image_urls)
    product = Product.find_by(id: product_id)
    return unless product

    return if image_urls.blank?

    # Limitar a MAX_IMAGES_PER_PRODUCT imágenes
    urls_to_download = image_urls.first(MAX_IMAGES_PER_PRODUCT)

    Rails.logger.info "Descargando #{urls_to_download.size} imágenes para producto #{product.asin}..."

    # Purgar imágenes existentes para reemplazarlas con las nuevas
    product.images.purge if product.images.attached?

    downloaded_count = 0

    urls_to_download.each do |url|
      next if url.blank?

      begin
        download_and_attach_image(product, url)
        downloaded_count += 1
      rescue StandardError => e
        Rails.logger.error "Error descargando imagen #{url}: #{e.message}"
      end
    end

    Rails.logger.info "Descarga completada: #{downloaded_count} imágenes adjuntadas al producto #{product.asin}"
  end

  private

  def download_and_attach_image(product, url)
    require 'open-uri'

    # Extraer el nombre del archivo de la URL
    filename = File.basename(URI.parse(url).path)

    # Descargar la imagen
    downloaded_image = URI.open(url)

    # Adjuntar al producto
    product.images.attach(
      io: downloaded_image,
      filename: filename,
      content_type: downloaded_image.content_type
    )

    Rails.logger.info "Imagen adjuntada: #{filename}"
  end
end

