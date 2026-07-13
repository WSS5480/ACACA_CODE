class AppSetting < ApplicationRecord
  validates :key, presence: true, uniqueness: true

  # Almacén simple clave/valor para configuraciones editables desde el admin
  # (por ejemplo, la API key de Rainforest). No se expone el valor en claro.
  def self.get(key, default = nil)
    find_by(key: key)&.value.presence || default
  end

  def self.set(key, value)
    record = find_or_initialize_by(key: key)
    record.value = value
    record.save!
    record
  end
end
