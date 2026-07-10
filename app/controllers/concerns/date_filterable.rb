# app/controllers/concerns/date_filterable.rb
module DateFilterable
  extend ActiveSupport::Concern

  private

  # Aplica filtro de rango de fechas a una colección
  # @param collection [ActiveRecord::Relation] La colección a filtrar
  # @param column [Symbol, String] La columna sobre la cual aplicar el filtro (default: :created_at)
  # @return [ActiveRecord::Relation] La colección filtrada
  def apply_date_filter(collection, column: :created_at)
    date_from = parse_date_param(params[:date_from], :beginning_of_day)
    date_to = parse_date_param(params[:date_to], :end_of_day)

    return collection if date_from.blank? && date_to.blank?

    table_name = collection.model.table_name
    qualified_column = "#{table_name}.#{column}"

    collection = collection.where("#{qualified_column} >= ?", date_from) if date_from
    collection = collection.where("#{qualified_column} <= ?", date_to) if date_to
    collection
  end

  # Parsea un parámetro de fecha y aplica el ajuste de inicio/fin de día
  # @param date_string [String, nil] La fecha en formato YYYY-MM-DD
  # @param day_boundary [Symbol] :beginning_of_day o :end_of_day
  # @return [Time, nil] La fecha parseada o nil si no es válida
  def parse_date_param(date_string, day_boundary)
    return nil if date_string.blank?

    Date.parse(date_string).public_send(day_boundary)
  rescue Date::Error
    raise InvalidDateFormatError, 'Formato de fecha inválido. Use el formato YYYY-MM-DD'
  end

  # Error personalizado para formato de fecha inválido
  class InvalidDateFormatError < StandardError; end
end

