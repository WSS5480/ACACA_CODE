# frozen_string_literal: true

# SOPORTE con TICKETS: cada solicitud de ayuda se registra por cliente y se
# gestiona hasta su resolución (abierto -> en proceso -> esperando cliente ->
# resuelto), con notas de seguimiento y todo en la Bitácora.
class CreateSupportTickets < ActiveRecord::Migration[7.1]
  def change
    unless table_exists?(:support_tickets)
      create_table :support_tickets do |t|
        t.bigint :user_id, index: true          # cliente (si tiene cuenta)
        t.string :customer_name                 # nombre visible (aunque no tenga cuenta)
        t.string :phone
        t.string :subject, null: false
        t.text :description
        t.string :channel, default: 'admin'     # whatsapp | admin | telefono | correo
        t.string :status, default: 'abierto'    # abierto | en_proceso | esperando_cliente | resuelto
        t.string :priority, default: 'media'    # baja | media | alta
        t.string :assigned_name                 # quién lo atiende
        t.text :resolution                      # cómo se resolvió (obligatorio al resolver)
        t.datetime :resolved_at
        t.string :created_by                    # quién lo registró (staff o 'Automático')
        t.timestamps
      end
      add_index :support_tickets, :status
    end

    unless table_exists?(:support_ticket_notes)
      create_table :support_ticket_notes do |t|
        t.bigint :support_ticket_id, null: false, index: true
        t.string :author_name
        t.text :body, null: false
        t.timestamps
      end
    end
  end
end
