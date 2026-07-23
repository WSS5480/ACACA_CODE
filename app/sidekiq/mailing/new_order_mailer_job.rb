class Mailing::NewOrderMailerJob
  include Sidekiq::Worker

  def perform(order_id)
    order = Order.find_by(id: order_id)
    return unless order

    UserMailer.with(order: order).send_new_order_notification.deliver_now
  end
end
