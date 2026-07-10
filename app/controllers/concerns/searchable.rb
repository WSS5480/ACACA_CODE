module Searchable
  extend ActiveSupport::Concern

  ACCENTED_CHARS = 'áéíóúàèìòùäëïöüâêîôûãõñÁÉÍÓÚÀÈÌÒÙÄËÏÖÜÂÊÎÔÛÃÕÑ'.freeze
  UNACCENTED_CHARS = 'aeiouaeiouaeiouaeiouaonAEIOUAEIOUAEIOUAEIOUAON'.freeze

  private

  def apply_search_filter(collection, columns:)
    return collection if params[:search].blank? || columns.empty?

    table_name = collection.model.table_name
    search_term = normalize_search_term(params[:search])
    search_pattern = "%#{sanitize_search_pattern(search_term)}%"

    conditions = columns.map { |column| "#{normalize_column(table_name, column)} LIKE :search" }.join(' OR ')
    collection.where(conditions, search: search_pattern)
  end

  def normalize_column(table_name, column)
    "LOWER(TRANSLATE(#{table_name}.#{column}, '#{ACCENTED_CHARS}', '#{UNACCENTED_CHARS}'))"
  end

  def normalize_search_term(term)
    ActiveSupport::Inflector.transliterate(term.to_s).downcase
  end

  def sanitize_search_pattern(term)
    # Escapar caracteres especiales de LIKE para evitar inyecciones
    term.gsub(/[%_]/) { |char| "\\#{char}" }
  end
end

