class ProductSerializer
  include JSONAPI::Serializer

  attributes :id, :title, :keywords, :asin, :original_link, :brand, :rating,
             :feature_bullets, :price, :price_with_discount, :currency, :color, :material,
             :dimensions, :model_number, :external_id, :status, :turns, :decimal_factor,
             :original_price, :created_at, :updated_at

  # Respuestas guardadas AL DESCARGAR (sin verificaciones posteriores):
  attribute :sold_by_amazon do |p|
    p.respond_to?(:sold_by_amazon) ? p.sold_by_amazon : nil
  end
  attribute :delivered_by_amazon do |p|
    p.respond_to?(:delivered_by_amazon) ? p.delivered_by_amazon : nil
  end
  attribute :main_photo_ok do |p|
    p.respond_to?(:main_photo_ok) ? p.main_photo_ok : nil
  end

  # PROMOCIÓN VIGENTE (se llena al descargar del modo Promociones y se revisa a
  # diario). promo_list_price_usd es el precio tachado que ve el cliente.
  attribute :promo do |p|
    p.respond_to?(:promo) ? !!p.promo : false
  end
  attribute :promo_percent_off do |p|
    p.respond_to?(:promo_percent_off) ? p.promo_percent_off : nil
  end
  attribute :promo_badge do |p|
    p.respond_to?(:promo_badge) ? p.promo_badge : nil
  end
  attribute :promo_list_price do |p|
    p.respond_to?(:promo_list_price) ? p.promo_list_price : nil
  end
  attribute :promo_list_price_usd do |p|
    p.respond_to?(:promo_list_price_usd) ? p.promo_list_price_usd : nil
  end

  # Vista (1-6) y orden dentro de la vista. Las promos cuentan como vista 0.
  attribute :catalog_view do |p|
    p.respond_to?(:catalog_view) ? p.catalog_view : nil
  end
  attribute :catalog_order do |p|
    p.respond_to?(:catalog_order) ? p.catalog_order : nil
  end
  attribute :effective_view do |p|
    p.respond_to?(:effective_view) ? p.effective_view : nil
  end

  attribute :min_weekly_payment do |product|
    product.recalculated_min_weekly_payment
  end

  attribute :total_price do |product|
    product.total_price
  end

  attribute :full_price do |product|
    product.full_price
  end

  attribute :image_urls do |product|
    product.image_urls
  end

  attribute :categories do |product|
    product.categories.map do |category|
      {
        id: category.id,
        name: category.name,
        external_id: category.external_id
      }
    end
  end
end

