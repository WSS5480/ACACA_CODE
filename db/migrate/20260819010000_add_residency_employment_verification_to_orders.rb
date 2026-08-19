# frozen_string_literal: true

# Verificación por SECCIONES en Órdenes: además de beneficiario, comprador y
# referencias, ahora RESIDENCIA (domicilio + contacto de domicilio + comprobante)
# y EMPLEO (trabajo + tel. del trabajo + comprobante de ingresos) se verifican
# por separado, cada una con su palomita y comentario.
class AddResidencyEmploymentVerificationToOrders < ActiveRecord::Migration[7.1]
  def change
    add_column :orders, :residency_verified, :boolean, default: false unless column_exists?(:orders, :residency_verified)
    add_column :orders, :residency_comment, :string unless column_exists?(:orders, :residency_comment)
    add_column :orders, :employment_verified, :boolean, default: false unless column_exists?(:orders, :employment_verified)
    add_column :orders, :employment_comment, :string unless column_exists?(:orders, :employment_comment)
  end
end
