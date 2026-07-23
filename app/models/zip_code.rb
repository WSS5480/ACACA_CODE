class ZipCode < ApplicationRecord
  validates :code, presence: true, uniqueness: true
  validates :state_initials, presence: true
  validates :state_name, presence: true
end
