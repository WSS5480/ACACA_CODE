# frozen_string_literal: true

# MIGRAR AL ARRANCAR EL PROCESO — la garantía definitiva.
#
# Historia: bin/docker-entrypoint corría db:prepare, pero el "Docker Command"
# de Render REEMPLAZA el entrypoint del contenedor, así que ese paso nunca se
# ejecutaba y los deploys salían con código nuevo sobre esquema viejo (así se
# quedó sin crear la tabla del gate de referencias, dos veces).
#
# Aquí es imposible de brincar: corre dentro del propio proceso de Rails al
# terminar de inicializar, se arranque como se arranque. El migrador de Rails
# toma un advisory lock en Postgres, así que dos arranques simultáneos no
# chocan. Si una migración falla, el proceso truena a propósito: mejor no
# arrancar que servir a medias. Sin migraciones pendientes cuesta una consulta.
Rails.application.config.after_initialize do
  next unless Rails.env.production?

  begin
    ctx = if ActiveRecord::Base.connection.respond_to?(:migration_context)
            ActiveRecord::Base.connection.migration_context
          else
            ActiveRecord::MigrationContext.new(ActiveRecord::Migrator.migrations_paths)
          end
    if ctx.needs_migration?
      Rails.logger.info '[migrate_on_boot] Aplicando migraciones pendientes…'
      ctx.migrate
      Rails.logger.info '[migrate_on_boot] Esquema al día.'
    end
  rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished => e
    # Sin base de datos alcanzable no hay nada que migrar desde aquí
    # (p. ej. una herramienta corriendo fuera del entorno real).
    Rails.logger.warn "[migrate_on_boot] BD no disponible: #{e.message}"
  end
end
