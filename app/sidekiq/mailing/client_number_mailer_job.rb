class Mailing::ClientNumberMailerJob
  include Sidekiq::Worker

  def perform(user_id)
    user = User.find_by(id: user_id)
    return unless user

    UserMailer.with(user: user).send_client_number.deliver_now
  end
end

