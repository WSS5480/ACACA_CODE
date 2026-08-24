# frozen_string_literal: true

# GASTO del negocio (para el estado de resultados). amount NEGATIVO = reversión
# (p.ej. al reactivar una cuenta castigada se revierte el gasto por incobrable).
class Expense < ApplicationRecord
  CATEGORIES = %w[producto envio comisiones publicidad nomina software incobrable otro].freeze

  validates :category, inclusion: { in: CATEGORIES }
  validates :amount, numericality: { other_than: 0 }
  validates :expense_date, presence: true
end
