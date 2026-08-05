# frozen_string_literal: true

# Contrato generado y firma electrónica del cliente:
# - document_text: el contrato RENDERIZADO (plantilla + datos) congelado al generarse
# - document_generated_at / document_sent_at: cuándo se generó y se avisó por WhatsApp
# - signed_at / signature_name / signature_ip: la firma del cliente (imagen en Active Storage)
class AddSignatureToContracts < ActiveRecord::Migration[7.1]
  def change
    add_column :contracts, :document_text, :text
    add_column :contracts, :document_generated_at, :datetime
    add_column :contracts, :document_sent_at, :datetime
    add_column :contracts, :signed_at, :datetime
    add_column :contracts, :signature_name, :string
    add_column :contracts, :signature_ip, :string
  end
end
