class ApplicationController < ActionController::API
  before_action :configure_permitted_parameters, if: :devise_controller?

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: %i[name last_name number email password password_confirmation phone housing_type months_usa months_address months_job estimated_income delivery_country shared_income role_id])
    devise_parameter_sanitizer.permit(:account_update, keys: %i[name last_name number email password password_confirmation phone housing_type months_usa months_address months_job estimated_income delivery_country shared_income role_id])
  end
end
