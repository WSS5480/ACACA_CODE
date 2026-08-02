# frozen_string_literal: true

# Una cuota (fila) de la tabla de amortizacion de un contrato.
class ContractInstallment < ApplicationRecord
  belongs_to :contract
  STATUSES = %w[pending partial paid].freeze
  validates :status, inclusion: { in: STATUSES }
end
