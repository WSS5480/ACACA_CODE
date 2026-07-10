class Guarantor < ApplicationRecord
  belongs_to :order

  has_one_attached :proof_of_address
  has_one_attached :identification

  validates :order, :name, :last_name, :phone, :email, presence: true
end
