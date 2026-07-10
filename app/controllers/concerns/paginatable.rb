module Paginatable
  extend ActiveSupport::Concern

  private

  def skip_pagination?
    params[:page] == '-1'
  end

  def order_direction
    params[:order].to_s.downcase == 'desc' ? :desc : :asc
  end

  def alphabetic_order?
    %w[az za].include?(params[:order].to_s.downcase)
  end

  def alphabetic_direction
    params[:order].to_s.downcase == 'za' ? :desc : :asc
  end

  def apply_order(collection, alphabetic_column = nil)
    table_name = collection.model.table_name

    if alphabetic_column && alphabetic_order?
      collection.order("#{table_name}.#{alphabetic_column}": alphabetic_direction)
    else
      collection.order("#{table_name}.created_at": order_direction)
    end
  end

  def pagination_meta(collection)
    {
      current_page: collection.current_page,
      next_page: collection.next_page,
      prev_page: collection.prev_page,
      total_pages: collection.total_pages,
      total_count: collection.total_count
    }
  end

  def paginate(collection)
    collection.page(params[:page]).per(params[:per_page])
  end

  def render_paginated(collection, serializer, alphabetic_column = nil)
    ordered = apply_order(collection, alphabetic_column)

    if skip_pagination?
      render json: {
        data: serializer.new(ordered).serializable_hash[:data],
        meta: { total_count: ordered.count }
      }, status: :ok
    else
      paginated = paginate(ordered)
      render json: {
        data: serializer.new(paginated).serializable_hash[:data],
        meta: pagination_meta(paginated)
      }, status: :ok
    end
  end
end

