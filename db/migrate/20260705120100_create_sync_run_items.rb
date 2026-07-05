class CreateSyncRunItems < ActiveRecord::Migration[8.1]
  def change
    create_table :sync_run_items do |t|
      t.references :sync_run, null: false, foreign_key: true
      t.references :indexer_app, null: false, foreign_key: true
      t.string :status, null: false, default: "queued"
      t.datetime :started_at
      t.datetime :finished_at
      t.text :error

      t.timestamps
    end

    add_index :sync_run_items, [ :sync_run_id, :status ]
    add_index :sync_run_items, [ :indexer_app_id, :created_at ]
  end
end
