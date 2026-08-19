# frozen_string_literal: true

# Nota de seguimiento de un ticket de soporte (bitácora del ticket).
class SupportTicketNote < ApplicationRecord
  belongs_to :support_ticket
  validates :body, presence: true
end
