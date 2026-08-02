class ApplicationMailer < ActionMailer::Base
  include LogoAttachable
  default from: "acasa <#{ENV['MAIL_FROM'] || ENV['SMTP_USERNAME'] || ENV['SMTP2GO_USERNAME']}>"
  layout "mailer"

  before_action :set_locale
  
  private
  
  def set_locale
    I18n.locale = :es
  end
end
