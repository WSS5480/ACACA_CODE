# frozen_string_literal: true

# Nuevas POSICIONES del equipo: Gerente, Administrador de cuentas y
# Administrador de Redes sociales (nivel operativo: operación diaria,
# sin administración de usuarios ni cambios sensibles).
class AddTeamRoles < ActiveRecord::Migration[7.1]
  NEW_ROLES = [
    %w[gerente Gerente],
    ['admin_cuentas', 'Administrador de cuentas'],
    ['admin_redes', 'Administrador de Redes sociales']
  ].freeze

  def up
    return unless table_exists?(:roles)

    NEW_ROLES.each do |name, label|
      next if select_value(ActiveRecord::Base.sanitize_sql(['SELECT id FROM roles WHERE name = ?', name]))

      execute ActiveRecord::Base.sanitize_sql(
        ['INSERT INTO roles (name, label, created_at, updated_at) VALUES (?, ?, NOW(), NOW())', name, label]
      )
    end
  end

  def down
    # Las posiciones se quedan: podrían tener usuarios asignados.
  end
end
