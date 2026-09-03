class Api::ZipCodesController < ApplicationController
  include TokenAuthenticatable
  include ClientOrTokenAuthenticatable
  include Paginatable
  include Searchable

  # Desactivar autenticaciones por defecto
  skip_before_action :authenticate_entity!
  skip_before_action :authenticate_client_or_user!
  # Nivel 2: Solo JWT para index, create, destroy, current_user
  before_action :authenticate_entity!, only: [:create, :update, :destroy, :populate]
  # Nivel 3: Cliente o JWT para show, update
  before_action :authenticate_client_or_user!, only: [:index, :show]

  before_action :set_zip_code, only: [:show, :update, :destroy]

  # GET /api/zip_codes
  def index
    zip_codes = filtered_zip_codes

    # Si piden UN código completo (5 dígitos) con país y NO está en la tabla,
    # se consulta el catálogo oficial en línea (zippopotam.us — datos de los
    # correos de EUA y México), se guarda como caché en zip_codes y se vuelve
    # a buscar. Así el autollenado del storefront nunca se queda mudo por un
    # hueco en la tabla, y todo queda verificado contra datos reales.
    full_zip = params[:search].to_s.gsub(/\D/, '')
    if full_zip.length == 5 && params[:country].present? && !zip_codes.exists?
      ZipLookup.fetch_and_cache(params[:country], full_zip)
      zip_codes = filtered_zip_codes
    end

    render_paginated(zip_codes, ZipCodeSerializer)
  end

  # GET /api/zip_codes/:id
  def show
    render json: ZipCodeSerializer.new(@zip_code).serializable_hash, status: :ok
  end

  # POST /api/zip_codes
  def create
    @zip_code = ZipCode.new(zip_code_params)

    if @zip_code.save
      render json: ZipCodeSerializer.new(@zip_code).serializable_hash, status: :created
    else
      render json: { errors: @zip_code.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PUT/PATCH /api/zip_codes/:id
  def update
    if @zip_code.update(zip_code_params)
      render json: ZipCodeSerializer.new(@zip_code).serializable_hash, status: :ok
    else
      render json: { errors: @zip_code.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /api/zip_codes/:id
  def destroy
    @zip_code.destroy
    head :no_content
  end

  # POST /api/zip_codes/populate
  # Params:
  #   - country: 'MX', 'US', or 'all' (default: 'all')
  #   - clear_existing: true/false - whether to delete existing records before populating (default: false)
  def populate
    country = params[:country] || 'all'
    clear_existing = ActiveModel::Type::Boolean.new.cast(params[:clear_existing]) || false

    result = ZipCodePopulatorService.new(
      country: country,
      clear_existing: clear_existing
    ).call

    if result[:success]
      render json: {
        message: 'Códigos postales poblados exitosamente',
        results: result[:results]
      }, status: :ok
    else
      render json: { error: result[:error] }, status: :unprocessable_entity
    end
  end

  private

  # Mismo filtro que siempre usó index, re-ejecutable después de cachear.
  def filtered_zip_codes
    scope = ZipCode.all
    scope = apply_search_filter(scope, columns: %w[code state_initials state_name city])
    scope = scope.where(country: params[:country]) if params[:country].present?
    scope
  end

  def set_zip_code
    @zip_code = ZipCode.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Código postal no encontrado' }, status: :not_found
  end

  def zip_code_params
    params.require(:zip_code).permit(:code, :country, :state_initials, :state_name, :city, :municipality, :settlement)
  end
end
