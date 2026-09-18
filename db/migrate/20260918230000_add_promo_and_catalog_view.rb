# frozen_string_literal: true

# PROMOCIONES Y ORDEN DEL CATÁLOGO.
#
# promo_*        : la oferta VIGENTE de Amazon para ese artículo (precio de lista
#                  tachado, % de descuento y la etiqueta que pone Amazon). Se llena
#                  al descargar desde el modo Promociones y se revisa a diario:
#                  cuando la oferta se acaba, promo vuelve a false y el artículo
#                  regresa a precio normal solo.
# catalog_view   : la vista (1 a 6) donde el equipo acomoda el artículo.
# catalog_order  : el orden DENTRO de esa vista (menor primero).
#
# Los artículos en promoción se muestran SIEMPRE primero (cuentan como vista 0)
# sin perder la vista que tenían: al terminar la oferta vuelven a su lugar.
class AddPromoAndCatalogView < ActiveRecord::Migration[7.1]
  def change
    add_column :products, :promo, :boolean, default: false, null: false
    add_column :products, :promo_list_price, :decimal, precision: 12, scale: 2
    add_column :products, :promo_percent_off, :integer
    add_column :products, :promo_badge, :string
    add_column :products, :promo_checked_at, :datetime
    add_column :products, :catalog_view, :integer, default: 1, null: false
    add_column :products, :catalog_order, :integer, default: 100, null: false

    add_index :products, :promo
    add_index :products, %i[catalog_view catalog_order]
  end
end
