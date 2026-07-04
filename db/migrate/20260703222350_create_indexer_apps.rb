class CreateIndexerApps < ActiveRecord::Migration[8.1]
  def change
    create_table :indexer_apps do |t|
      t.references :indexer, null: false, foreign_key: true
      t.references :arr_app, null: false, foreign_key: true
      t.boolean :enabled, null: false, default: true
      t.integer :remote_indexer_id
      t.datetime :last_synced_at
      t.string :last_status
      t.text :last_error

      t.timestamps
    end

    add_index :indexer_apps, [ :indexer_id, :arr_app_id ], unique: true
  end
end
