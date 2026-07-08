class AddRetryMetadataToSyncRunItems < ActiveRecord::Migration[8.1]
  def change
    add_column :sync_run_items, :attempt_count, :integer, null: false, default: 0
    add_column :sync_run_items, :max_attempts, :integer, null: false, default: 2
    add_column :sync_run_items, :last_attempt_at, :datetime
    add_column :sync_run_items, :next_retry_at, :datetime

    add_index :sync_run_items, [ :status, :next_retry_at ]
  end
end
