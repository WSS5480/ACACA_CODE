class Api::RolesController < ApplicationController
  include TokenAuthenticatable
  before_action :set_role, only: [:show, :update, :destroy]

  # GET /api/roles
  def index
    @roles = Role.all
    render json: @roles
  end

  # GET /api/roles/:id
  def show
    render json: @role
  end

  # POST /api/roles
  def create
    @role = Role.new(role_params)

    if @role.save
      render json: @role, status: :created
    else
      render json: { errors: @role.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /api/roles/:id
  def update
    if @role.update(role_params)
      render json: @role
    else
      render json: { errors: @role.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /api/roles/:id
  def destroy
    @role.destroy
    head :no_content
  end

  # POST /api/roles/seed
  def seed
    default_roles = [
      { name: 'master', label: 'Master' },
      { name: 'admin', label: 'Admin' },
      { name: 'sistema', label: 'Sistema' },
      { name: 'editor', label: 'Editor' },
      { name: 'operador', label: 'Operador' },
      { name: 'cliente', label: 'Cliente' }
    ]

    created_roles = []
    existing_roles = []

    default_roles.each do |role_data|
      role = Role.find_by(name: role_data[:name])
      if role
        existing_roles << role
      else
        created_roles << Role.create!(role_data)
      end
    end

    render json: {
      message: 'Seed completed',
      created: created_roles,
      already_existed: existing_roles
    }, status: :ok
  end

  private

  def set_role
    @role = Role.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Role not found' }, status: :not_found
  end

  def role_params
    params.require(:role).permit(:name, :label)
  end
end

