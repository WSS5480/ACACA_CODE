class Mailing::WelcomeUserJob
  include Sidekiq::Job

  def perform(user_id, pwrd = nil)
    user = User.find_by(id: user_id)
    return unless user && user.email
    UserMailer.with(user: user, pwrd: pwrd).send_welcome.deliver_now
  end
end
