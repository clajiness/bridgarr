class ReclassifyIncompatibleAssignmentPlans < ActiveRecord::Migration[8.1]
  class MigrationIndexerApp < ActiveRecord::Base
    self.table_name = "indexer_apps"
  end

  def up
    return unless column_exists?(:indexer_apps, :last_plan_state)
    return unless column_exists?(:indexer_apps, :last_status)
    return unless column_exists?(:indexer_apps, :last_error)

    MigrationIndexerApp
      .where(last_plan_state: "invalid", last_status: "skipped")
      .where(<<~SQL.squish)
        LOWER(COALESCE(last_error, '')) LIKE '%no compatible default categories%'
        OR LOWER(COALESCE(last_error, '')) LIKE '%does not expose %compatible torznab categories%'
      SQL
      .update_all(last_plan_state: "not_applicable")
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "The prior invalid state cannot be distinguished from genuine invalid configurations."
  end
end
