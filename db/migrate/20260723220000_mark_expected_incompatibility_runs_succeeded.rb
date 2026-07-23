class MarkExpectedIncompatibilityRunsSucceeded < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      UPDATE sync_runs
      SET status = 'succeeded', updated_at = CURRENT_TIMESTAMP
      WHERE status IN ('partial', 'skipped')
        AND failure_count = 0
        AND mismatch_count = 0
        AND skipped_count > 0
        AND EXISTS (
          SELECT 1
          FROM sync_run_items
          WHERE sync_run_items.sync_run_id = sync_runs.id
            AND sync_run_items.status = 'skipped'
            AND sync_run_items.error_kind = 'incompatible_categories'
        )
        AND NOT EXISTS (
          SELECT 1
          FROM sync_run_items
          WHERE sync_run_items.sync_run_id = sync_runs.id
            AND sync_run_items.status = 'skipped'
            AND COALESCE(sync_run_items.error_kind, '') <> 'incompatible_categories'
        )
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Corrected sync-run outcomes cannot be distinguished from newer successful runs."
  end
end
