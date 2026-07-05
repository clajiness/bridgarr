class CreateSyncRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :sync_runs do |t|
      t.string :status, null: false, default: "queued"
      t.string :mode, null: false, default: "bulk"
      t.integer :total_count, null: false, default: 0
      t.integer :success_count, null: false, default: 0
      t.integer :failure_count, null: false, default: 0
      t.datetime :started_at
      t.datetime :finished_at
      t.text :error

      t.timestamps
    end

    add_index :sync_runs, [ :status, :created_at ]
    add_index :sync_runs, :mode
  end
end
