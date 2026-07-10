class CreateRiskEngineConfigs < ActiveRecord::Migration[7.1]
  def up
    create_table :risk_engine_configs do |t|
      t.integer :version, null: false
      t.text :notes
      t.jsonb :config, null: false, default: {}
      t.boolean :active, null: false, default: false
      t.timestamps
    end
    add_index :risk_engine_configs, :version, unique: true
    add_index :risk_engine_configs, :active

    RiskEngineConfig.reset_column_information

    base = {
      'housing'         => { 'owner' => 5 },
      'months'          => [[48, 20], [24, 15], [12, 10], [6, 5]],
      'kinship_default' => 20,
      'delivery'        => 5,
      'credit'          => [[79, 750], [69, 600], [59, 500], [49, 400], [45, 300]]
    }

    # Versión 1 — comportamiento original
    RiskEngineConfig.create!(
      version: 1,
      active: false,
      notes: 'Versión original: parentesco fijo en 20 pts (no usaba la respuesta real); ingreso >= $750 daba 25 pts (igual que >= $500).',
      config: base.merge(
        'income'  => [[750, 25], [500, 25], [400, 20], [300, 15], [200, 10], [100, 5]],
        'kinship' => { 'conyuge' => 20, 'cónyuge' => 20, 'esposo' => 20, 'esposa' => 20,
                       'hijo' => 20, 'hija' => 20, 'padre' => 20, 'madre' => 20,
                       'hermano' => 20, 'hermana' => 20, 'otro' => 20 }
      )
    )

    # Versión 2 — activa
    RiskEngineConfig.create!(
      version: 2,
      active: true,
      notes: 'Parentesco puntuado con la respuesta real (Conyuge/Hijo/Padre 20, Hermano 15, Otro 10). Ingreso >= $750 ahora otorga 30 pts.',
      config: base.merge(
        'income'  => [[750, 30], [500, 25], [400, 20], [300, 15], [200, 10], [100, 5]],
        'kinship' => { 'conyuge' => 20, 'cónyuge' => 20, 'esposo' => 20, 'esposa' => 20,
                       'hijo' => 20, 'hija' => 20, 'padre' => 20, 'madre' => 20,
                       'hermano' => 15, 'hermana' => 15, 'otro' => 10 }
      )
    )
  end

  def down
    drop_table :risk_engine_configs
  end
end
