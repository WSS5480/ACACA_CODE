# frozen_string_literal: true

require 'net/http'

# Marketing en Meta: publicar/programar en la página de FACEBOOK, publicar en
# INSTAGRAM (cuenta business ligada a la página), leer publicaciones,
# comentarios y métricas, y responder comentarios — con la misma app de Meta
# que ya usa WhatsApp.
#
# ENV:
#   META_MKT_TOKEN  token de usuario del sistema con permisos de páginas/IG
#                   (si no está, se intenta con WHATSAPP_TOKEN)
#   FB_PAGE_ID      id de la página de Facebook
#   IG_USER_ID      (opcional) id de la cuenta IG business; si falta, se
#                   detecta sola desde la página (instagram_business_account)
class MetaMarketing
  GRAPH = 'https://graph.facebook.com/v25.0'

  class NotConfigured < StandardError; end

  def self.configured?
    (ENV['META_MKT_TOKEN'].presence || ENV['WHATSAPP_TOKEN']).present? && ENV['FB_PAGE_ID'].present?
  end

  def initialize
    raise NotConfigured, 'Configura META_MKT_TOKEN (o WHATSAPP_TOKEN) y FB_PAGE_ID' unless self.class.configured?

    @token = ENV['META_MKT_TOKEN'].presence || ENV['WHATSAPP_TOKEN']
    @page = ENV['FB_PAGE_ID']
  end

  # ---------- lecturas ----------

  def overview
    pg = get(@page, fields: 'name,fan_count,followers_count,link')
    igp = ig_id ? get(ig_id, fields: 'username,followers_count,media_count') : nil
    reach = begin
      r = get("#{@page}/insights", metric: 'page_impressions_unique', period: 'day', access: :page)
      vals = r.dig('data', 0, 'values') || []
      vals.last(7).map { |v| { date: v['end_time'].to_s[0, 10], value: v['value'].to_i } }
    rescue StandardError
      []
    end
    { fb: pg, ig: igp, reach_daily: reach }
  end

  def posts
    out = []
    fb = get("#{@page}/posts",
             fields: 'message,created_time,full_picture,permalink_url,shares,likes.summary(true),comments.summary(true)',
             limit: 12, access: :page)
    (fb['data'] || []).each do |p|
      out << { network: 'fb', id: p['id'], text: p['message'], at: p['created_time'],
               img: p['full_picture'], url: p['permalink_url'],
               likes: p.dig('likes', 'summary', 'total_count').to_i,
               comments: p.dig('comments', 'summary', 'total_count').to_i,
               shares: p.dig('shares', 'count').to_i }
    end
    begin
      sc = get("#{@page}/scheduled_posts", fields: 'message,scheduled_publish_time,full_picture', limit: 10, access: :page)
      (sc['data'] || []).each do |p|
        out << { network: 'fb', id: p['id'], text: p['message'],
                 at: (p['scheduled_publish_time'].is_a?(Integer) ? Time.at(p['scheduled_publish_time']).iso8601 : p['scheduled_publish_time']),
                 img: p['full_picture'], scheduled: true }
      end
    rescue StandardError
      nil
    end
    if ig_id
      ig = get("#{ig_id}/media", fields: 'caption,media_url,permalink,timestamp,like_count,comments_count', limit: 12)
      (ig['data'] || []).each do |m|
        out << { network: 'ig', id: m['id'], text: m['caption'], at: m['timestamp'],
                 img: m['media_url'], url: m['permalink'],
                 likes: m['like_count'].to_i, comments: m['comments_count'].to_i }
      end
    end
    out.sort_by { |p| p[:at].to_s }.reverse
  end

  def comments
    list = []
    fb = get("#{@page}/posts", fields: 'message,comments.limit(8){message,from,created_time}', limit: 8, access: :page)
    (fb['data'] || []).each do |p|
      (p.dig('comments', 'data') || []).each do |c|
        next if c.dig('from', 'id').to_s == @page.to_s # nuestras propias respuestas

        list << { network: 'fb', id: c['id'], author: c.dig('from', 'name') || 'Usuario de Facebook',
                  text: c['message'], at: c['created_time'], post: p['message'].to_s[0, 60] }
      end
    end
    if ig_id
      ig = get("#{ig_id}/media", fields: 'caption,comments.limit(8){text,username,timestamp}', limit: 8)
      (ig['data'] || []).each do |m|
        (m.dig('comments', 'data') || []).each do |c|
          list << { network: 'ig', id: c['id'], author: c['username'] || 'Usuario de Instagram',
                    text: c['text'], at: c['timestamp'], post: m['caption'].to_s[0, 60] }
        end
      end
    end
    list.sort_by { |c| c[:at].to_s }.reverse.first(40)
  end

  # ---------- acciones ----------

  # Publica (o programa) en las redes elegidas. IG requiere imagen y no permite
  # programar por API (limitación de Meta).
  def publish(message:, image_url: nil, networks: ['fb'], scheduled_at: nil)
    results = {}
    if networks.include?('fb')
      extra = {}
      if scheduled_at
        extra[:published] = 'false'
        extra[:scheduled_publish_time] = scheduled_at.to_i
      end
      results[:fb] = if image_url.present?
                       post("#{@page}/photos", { url: image_url, caption: message.to_s }.merge(extra), access: :page)
                     else
                       post("#{@page}/feed", { message: message.to_s }.merge(extra), access: :page)
                     end
    end
    if networks.include?('ig')
      results[:ig] = if ig_id.blank?
                       { 'error' => { 'message' => 'No hay cuenta de Instagram business ligada a la página.' } }
                     elsif image_url.blank?
                       { 'error' => { 'message' => 'Instagram requiere una imagen (URL pública).' } }
                     elsif scheduled_at
                       { 'error' => { 'message' => 'Meta no permite PROGRAMAR en Instagram por API: publícalo al momento.' } }
                     else
                       c = post("#{ig_id}/media", image_url: image_url, caption: message.to_s)
                       c['id'] ? post("#{ig_id}/media_publish", creation_id: c['id']) : c
                     end
    end
    results
  end

  # Responder un comentario (FB o IG).
  def reply(comment_id:, message:, network:)
    if network == 'ig'
      post("#{comment_id}/replies", message: message.to_s)
    else
      post("#{comment_id}/comments", { message: message.to_s }, access: :page)
    end
  end

  private

  # Id de la cuenta de Instagram business (env o detectada desde la página).
  def ig_id
    return @ig_id if defined?(@ig_id)

    @ig_id = ENV['IG_USER_ID'].presence || begin
      get(@page, fields: 'instagram_business_account').dig('instagram_business_account', 'id')
    rescue StandardError
      nil
    end
  end

  # Token de PÁGINA (necesario para publicar/leer como la página); se obtiene
  # con el token del usuario del sistema. Si falla, se usa el token general.
  def page_token
    @page_token ||= begin
      get(@page, fields: 'access_token')['access_token'].presence || @token
    rescue StandardError
      @token
    end
  end

  def get(path, params = {})
    access = params.delete(:access)
    tok = access == :page ? page_token : @token
    uri = URI("#{GRAPH}/#{path}")
    uri.query = URI.encode_www_form(params.merge(access_token: tok))
    parse(Net::HTTP.get_response(uri))
  end

  def post(path, params = {}, access: nil)
    tok = access == :page ? page_token : @token
    uri = URI("#{GRAPH}/#{path}")
    parse(Net::HTTP.post_form(uri, params.merge(access_token: tok)))
  end

  def parse(res)
    JSON.parse(res.body)
  rescue StandardError
    { 'error' => { 'message' => "Respuesta inválida de Meta (#{res&.code})" } }
  end
end
