class AddSkippedAndErrorMetadataToSyncRuns < ActiveRecord::Migration[8.0]
  def change
    add_column :sync_runs, :skipped_count, :integer, null: false, default: 0
    add_column :sync_run_items, :error_kind, :string
    add_column :sync_run_items, :retryable, :boolean, null: false, default: false
  end
end
