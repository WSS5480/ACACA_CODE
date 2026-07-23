module LogoAttachable
  extend ActiveSupport::Concern

  included do
    before_action :attach_logo
  end

  private

  def attach_logo
    # Usar PNG para mejor compatibilidad en correos electrónicos
    attachments.inline['acasa_logo_mail.png'] = File.read(Rails.root.join('public', 'acasa_logo_mail.png'))
  end
end