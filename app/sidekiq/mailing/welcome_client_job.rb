class Mailing::WelcomeClientJob
  include Sidekiq::Job

  def perform(user_id)
    user = User.find_by(id: user_id)
    return unless user && user.email

    UserMailer.with(user: user).send_client_welcome.deliver_now
  end
end

