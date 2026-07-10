class Products::ImportCsvJob
  include Sidekiq::Job

  # TTL de 2 horas para el resultado en Redis
  RESULT_TTL = 2.hours.to_i

  # Prefijo para las keys en Redis
  REDIS_KEY_PREFIX = 'csv_import_job'.freeze

  def perform(job_id, csv_content)
    return if csv_content.blank?

    Rails.logger.info "[Products::ImportCsvJob] Iniciando importación de CSV (job_id: #{job_id})..."

    # Marcar como procesando
    save_to_redis(job_id, { status: 'processing' })

    result = ProductCsvImporterService.call(csv_content)

    # Guardar resultado completo en Redis
    save_to_redis(job_id, {
      status: 'completed',
      result: result
    })

    Rails.logger.info "[Products::ImportCsvJob] Importación completada (job_id: #{job_id}): #{format_result(result)}"

    result
  rescue StandardError => e
    # Guardar error en Redis
    save_to_redis(job_id, {
      status: 'failed',
      error: e.message
    })

    Rails.logger.error "[Products::ImportCsvJob] Error (job_id: #{job_id}): #{e.message}"
    raise e
  end

  # Método de clase para consultar el resultado desde Redis
  def self.fetch_result(job_id)
    redis_key = "#{REDIS_KEY_PREFIX}:#{job_id}"

    Sidekiq.redis do |conn|
      data = conn.get(redis_key)
      return nil unless data

      JSON.parse(data, symbolize_names: true)
    end
  end

  private

  def save_to_redis(job_id, data)
    redis_key = "#{REDIS_KEY_PREFIX}:#{job_id}"

    Sidekiq.redis do |conn|
      conn.setex(redis_key, RESULT_TTL, data.to_json)
    end
  end

  def format_result(result)
    "Total: #{result[:total_rows]}, " \
    "Actualizados: #{result[:updated]}, " \
    "No encontrados: #{result[:not_found]}, " \
    "Omitidos: #{result[:skipped]}, " \
    "Errores: #{result[:errors].size}"
  end
end
