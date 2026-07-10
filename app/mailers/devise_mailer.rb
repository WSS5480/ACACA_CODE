class DeviseMailer < Devise::Mailer
  # Include this if using Devise's default layout
  include Devise::Mailers::Helpers
  include LogoAttachable
  layout 'mailer'

  def reset_password_instructions(record, token, opts={})
    @token = token
    opts[:subject] = 'Instrucciones para reestablecer contraseña'
    devise_mail(record, :reset_password_instructions, opts)
  end

end