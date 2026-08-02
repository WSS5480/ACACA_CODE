# frozen_string_literal: true

# Mensaje de WhatsApp archivado (entrante o saliente) ligado al cliente.
class WhatsappMessage < ApplicationRecord
  belongs_to :user, optional: true
  has_one_attached :media

  validates :direction, inclusion: { in: %w[in out] }

  scope :for_user, ->(uid) { where(user_id: uid).order(:created_at) }

  def media_url
    return nil unless media.attached?
    media.url(expires_in: 1.hour)
  rescue StandardError
    begin
      Rails.application.routes.url_helpers.rails_blob_url(media, only_path: false)
    rescue StandardError
      nil
    end
  end
end
