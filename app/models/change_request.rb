# frozen_string_literal: true

# Cambio PROPUESTO a configuración sensible: Tasas e impuestos, el documento
# legal del contrato, o la revocación de acceso de un usuario del equipo.
# Requiere FIRMAS de administradores para aplicarse: 4 en total (la del
# proponente cuenta como la primera), o TODAS las de los admins existentes si
# hay menos de 4. Los usuarios con rol 'sistema' aplican sus cambios directo.
# El cambio y cada firma quedan guardados SIEMPRE (aplicado o rechazado) y
# todo se registra en la bitácora de auditoría.
class ChangeRequest < ApplicationRecord
  KINDS = {
    'rates'             => 'Tasas e impuestos',
    'contract_template' => 'Control de documentos legales',
    'staff_delete'      => 'Revocar acceso del equipo'
  }.freeze

  has_many :change_signatures, dependent: :destroy

  validates :kind, inclusion: { in: KINDS.keys }

  scope :pending, -> { where(status: 'pending') }

  # Quiénes pueden firmar: master y admin.
  def self.signers_pool
    User.joins(:role).where(roles: { name: %w[master admin] })
  end

  # Crea la propuesta con la PRIMERA firma (la del proponente) y avisa por
  # correo al resto de los administradores. Si con eso ya no faltan firmas
  # (equipo chico), el cambio se aplica de inmediato.
  # exclude_id: usuario que NO puede firmar ni recibe aviso (p.ej. el admin
  # cuyo acceso se propone revocar).
  def self.propose!(kind:, payload:, summary:, proposer:, exclude_id: nil)
    pool = signers_pool.to_a.reject { |u| exclude_id && u.id == exclude_id }
    required = [[pool.size, 1].max, 4].min
    cr = create!(
      kind: kind, payload: payload.to_json, summary: summary,
      proposed_by_id: proposer&.id, proposed_by_email: proposer&.email,
      status: 'pending', required_signatures: required
    )
    AuditLog.record!(actor: proposer, action: 'change_proposed', target: cr,
                     label: KINDS[kind], details: "#{summary} · requiere #{required} firma(s)")
    cr.add_signature!(proposer) if proposer
    if cr.reload.status == 'pending'
      pool.reject { |u| u.id == proposer&.id || u.email.blank? }.each do |admin|
        UserMailer.with(user: admin, change: cr).send_change_approval.deliver_now
      rescue StandardError => e
        Rails.logger.error "No se pudo avisar a #{admin.email} del cambio ##{cr.id}: #{e.message}"
      end
    end
    cr
  end

  # Firma de un admin. Al reunir las firmas requeridas, el cambio SE APLICA.
  def add_signature!(user)
    return if status != 'pending' || user.nil?
    return if change_signatures.exists?(user_id: user.id)

    change_signatures.create!(user_id: user.id, user_email: user.email,
                              user_role: user.role&.name, signed_at: Time.current)
    AuditLog.record!(actor: user, action: 'change_signed', target: self,
                     label: KINDS[kind],
                     details: "#{summary} · firma #{change_signatures.count}/#{required_signatures}")
    apply!(actor: user) if change_signatures.count >= required_signatures
  end

  # Aplica el cambio propuesto (al completar firmas, o directo para 'sistema').
  def apply!(actor: nil)
    data = begin
      JSON.parse(payload.presence || '{}')
    rescue StandardError
      {}
    end
    sig_note = " · aplicado con #{change_signatures.count} firma(s)"
    case kind
    when 'rates'
      data.each { |k, v| AppSetting.set(k, v.to_s) }
      AuditLog.record!(actor: actor, action: 'rates_updated',
                       label: 'Tasas e impuestos', details: summary.to_s + sig_note)
    when 'contract_template'
      if data['reset']
        AppSetting.find_by(key: 'contract_template')&.destroy
        AuditLog.record!(actor: actor, action: 'template_reset',
                         label: 'Control de documentos legales',
                         details: 'Restauró la plantilla original' + sig_note)
      else
        AppSetting.set('contract_template', data['content'].to_s)
        AuditLog.record!(actor: actor, action: 'template_updated',
                         label: 'Control de documentos legales', details: summary.to_s + sig_note)
      end
    when 'staff_delete'
      u = User.find_by(id: data['user_id'])
      if u
        u.destroy!
        AuditLog.record!(actor: actor, action: 'staff_deleted', target: u,
                         label: [u.name, u.last_name].compact.join(' ').strip.presence || u.email,
                         details: summary.to_s + sig_note)
      end
    end
    update!(status: 'applied', applied_at: Time.current)
  end

  def reject!(actor)
    update!(status: 'rejected', rejected_by_email: actor&.email)
    AuditLog.record!(actor: actor, action: 'change_rejected', target: self,
                     label: KINDS[kind], details: summary)
  end

  def as_api
    {
      id: id, kind: kind, kind_label: KINDS[kind], summary: summary, status: status,
      proposed_by_id: proposed_by_id, proposed_by_email: proposed_by_email,
      required_signatures: required_signatures,
      signatures: change_signatures.order(:signed_at).map do |s|
        { user_id: s.user_id, user_email: s.user_email, user_role: s.user_role, signed_at: s.signed_at }
      end,
      created_at: created_at, applied_at: applied_at, rejected_by_email: rejected_by_email
    }
  end

  # Id del usuario objetivo en una revocación de acceso (para bloquear su firma).
  def target_user_id
    return nil unless kind == 'staff_delete'
    JSON.parse(payload.to_s)['user_id'].to_i
  rescue StandardError
    nil
  end
end
