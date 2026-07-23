# frozen_string_literal: true

module FillRecordFromUser
  extend ActiveSupport::Concern

  private

  # Rellena los atributos en blanco del record con los valores del usuario asociado.
  #
  # @param record [ApplicationRecord] El modelo a rellenar (debe estar asociado a un usuario,
  #   directa o indirectamente, p. ej. buyer → order → user).
  # @param column_names [Array<String, Symbol>] Cada elemento puede ser:
  #   - Un nombre simple (p. ej. "name"): se usa el mismo nombre en record y user.
  #   - Un mapeo "record_column:user_column" (p. ej. "phone_work:phone"): la columna del record
  #     se rellena con la columna del user.
  # @param user [User, nil] Usuario del que copiar valores. Si es nil, se obtiene del record
  #   (record.user o record.order.user).
  # @return [void]
  def fill_record_from_user(record, column_names, user = nil)
    user ||= user_from_record(record)
    return if user.blank?

    Array(column_names).each do |spec|
      spec = spec.to_s
      record_column, user_column = spec.include?(':') ? spec.split(':', 2).map(&:strip) : [spec, spec]
      next if record_column.blank? || user_column.blank?

      next unless record.respond_to?(:"#{record_column}=") && record.has_attribute?(record_column)
      next unless user.respond_to?(user_column)

      record.public_send(:"#{record_column}=", user.public_send(user_column)) if record.public_send(record_column).blank?
    end
  end

  def user_from_record(record)
    record.try(:user) || record.try(:order)&.try(:user)
  end
end
