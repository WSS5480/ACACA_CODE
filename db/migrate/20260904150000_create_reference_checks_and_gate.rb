class CreateReferenceChecksAndGate < ActiveRecord::Migration[7.1]
  def change
    create_table :reference_checks do |t|
      t.references :contract, null: false, foreign_key: true
      t.references :reference_ping, foreign_key: true
      t.string  :field            # 'months_address' | 'months_job'
      t.integer :claimed_months   # lo que dijo el CLIENTE (piso del rango, en meses)
      t.string  :claimed_bucket   # 'a' | 'b' | 'c'
      t.string  :reported_bucket  # lo que dijo la REFERENCIA
      t.integer :bucket_delta     # con SIGNO: + sobreestimó, - subestimó
      t.boolean :boundary, default: false # reclamo exactamente en el borde del rango
      t.string  :source_kind      # 'domicilio' | 'trabajo_empleador' | 'trabajo_referencia'
      t.integer :response_minutes
      t.timestamps
    end
    add_index :reference_checks, [:contract_id, :field, :source_kind], name: 'idx_ref_checks_scope'

    add_column :contracts, :reference_gate_status,  :string
    add_column :contracts, :reference_gate_reasons, :text
    add_column :contracts, :reference_gate_at,      :datetime
  end
end
