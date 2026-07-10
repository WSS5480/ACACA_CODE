class Mailing::PasswordResetMailerJob
  include Sidekiq::Worker

  def perform(user_id, token)
    user = User.find_by(id: user_id)
    return unless user
    DeviseMailer.reset_password_instructions(user, token).deliver_now
  end
end