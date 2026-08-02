# frozen_string_literal: true

module Api
  class AutopayController < ApplicationController
    # POST /api/autopay/run  (header X-Autopay-Token debe coincidir con AUTOPAY_SECRET)
    def run
      secret = ENV['AUTOPAY_SECRET']
      if secret.blank? || !ActiveSupport::SecurityUtils.secure_compare(request.headers['X-Autopay-Token'].to_s, secret)
        return render(json: { error: 'No autorizado' }, status: :forbidden)
      end
      render json: AutopayService.run, status: :ok
    end
  end
end
