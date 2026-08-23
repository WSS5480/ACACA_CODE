# frozen_string_literal: true

# RONDA AUTOMÁTICA DEL CATÁLOGO (gratis, sin créditos de Rainforest).
#
# Cada tick (15 min) revisa un LOTE de productos activos contra su página
# pública de Amazon: ¿sigue publicado? ¿la foto principal sigue siendo la
# nuestra? El cursor avanza y da la vuelta, así el catálogo COMPLETO se
# recorre solo — con miles de SKUs, un lote de 25 cada 15 min cubre ~2,400
# al día sin golpear a Amazon ni al servidor.
#
# Si encuentra problemas (ya no está publicado, o Amazon cambió la foto
# principal), avisa por WhatsApp interno (WaAlert) y lo deja en la Bitácora.
class CatalogPatrol
  CURSOR_KEY = 'catalog_patrol_cursor'

  def self.run!(batch: 15)
    return { omitido: 'sin productos' } unless Product.where(status: 'active').exists?

    cursor = AppSetting.get(CURSOR_KEY, '0').to_i
    scope  = Product.where(status: 'active').order(:id)
    lote   = scope.where('id > ?', cursor).limit(batch).to_a
    if lote.empty? # fin de la vuelta: empezar de nuevo
      lote = scope.limit(batch).to_a
    end
    return { omitido: 'sin lote' } if lote.empty?

    issues = []
    lote.each do |p|
      r = AmazonPageCheck.call(p)
      if r[:available] == false
        issues << "#{p.asin} · #{p.title.to_s.truncate(40)}: YA NO está publicado en Amazon"
        AuditLog.record!(actor: nil, action: 'catalog_issue', target: p, label: p.asin,
                         details: "Ya no está publicado en Amazon (#{r[:reason]})")
      elsif r[:photo_match] == false
        issues << "#{p.asin} · #{p.title.to_s.truncate(40)}: Amazon CAMBIÓ la foto principal"
        AuditLog.record!(actor: nil, action: 'catalog_issue', target: p, label: p.asin,
                         details: 'Amazon cambió la foto principal del listado (revisar posible cambio de modelo)')
      end
      sleep 0.5 # respirar entre páginas para no parecer bot
    end

    AppSetting.set(CURSOR_KEY, lote.last.id.to_s)

    if issues.any? && defined?(WaAlert)
      WaAlert.notify('Ronda del catálogo',
                     "#{issues.size} producto(s) con problema:\n- #{issues.first(8).join("\n- ")}#{issues.size > 8 ? "\n…y #{issues.size - 8} más (ver Bitácora)" : ''}")
    end

    { revisados: lote.size, problemas: issues.size, cursor: lote.last.id }
  rescue StandardError => e
    Rails.logger.error "[catalog_patrol] #{e.message}"
    { error: e.message }
  end
end
