# frozen_string_literal: true

class AddWhatsappVerificationToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :whatsapp_verify_token, :string
    add_index :users, :whatsapp_verify_token, unique: true
  end
end
