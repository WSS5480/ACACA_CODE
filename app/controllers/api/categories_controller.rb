class Api::CategoriesController < ApplicationController
  include TokenAuthenticatable
  include Paginatable
  include Searchable

  skip_before_action :authenticate_entity!, only: [:index]

  before_action :set_category, only: [:show, :update, :destroy]
  before_action :validate_external_id_uniqueness, only: [:create, :update]

  # GET /api/categories
  def index
    categories = Category.all
    categories = apply_search_filter(categories, columns: %w[name external_id])
    render_paginated(categories, CategorySerializer)
  end

  # GET /api/categories/:id
  def show
    render json: CategorySerializer.new(@category).serializable_hash, status: :ok
  end

  # POST /api/categories
  def create
    @category = Category.new(category_params)

    if @category.save
      render json: CategorySerializer.new(@category).serializable_hash, status: :created
    else
      render json: { errors: @category.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /api/categories/:id
  def update
    if @category.update(category_params)
      render json: CategorySerializer.new(@category).serializable_hash, status: :ok
    else
      render json: { errors: @category.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /api/categories/:id
  def destroy
    @category.destroy
    head :no_content
  end

  private

  def set_category
    @category = Category.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Categoría no encontrada' }, status: :not_found
  end

  def category_params
    params.require(:category).permit(:name, :external_id, :original_link)
  end

  def validate_external_id_uniqueness
    external_id = params.dig(:category, :external_id)
    return if external_id.blank?

    existing_category = Category.find_by(external_id: external_id)

    # En update, ignorar si es la misma categoría
    if action_name == 'update'
      return if existing_category.nil? || existing_category.id == @category.id
    end

    if existing_category.present?
      render json: { errors: ['El external_id ya existe en otra categoría'] }, status: :unprocessable_entity
    end
  end
end

