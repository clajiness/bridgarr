class AddMismatchCountToSyncRuns < ActiveRecord::Migration[8.0]
  def change
    add_column :sync_runs, :mismatch_count, :integer, null: false, default: 0
  end
end
