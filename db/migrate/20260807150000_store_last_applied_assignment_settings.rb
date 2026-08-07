class StoreLastAppliedAssignmentSettings < ActiveRecord::Migration[8.1]
  class MigrationIndexerApp < ActiveRecord::Base
    self.table_name = "indexer_apps"
  end

  def up
    add_column :indexer_apps, :last_applied_settings, :json unless column_exists?(:indexer_apps, :last_applied_settings)
    MigrationIndexerApp.reset_column_information

    MigrationIndexerApp
      .where(last_status: "ok", last_plan_state: "unchanged")
      .where.not(last_applied_at: nil)
      .where(last_applied_settings: nil)
      .find_each do |assignment|
        assignment.update_columns(
          last_applied_settings: {
            "enabled" => assignment.enabled,
            "connection_mode" => assignment.connection_mode,
            "category_mode" => assignment.category_mode,
            "custom_categories" => assignment.custom_categories
          }
        )
      end
  end

  def down
    remove_column :indexer_apps, :last_applied_settings if column_exists?(:indexer_apps, :last_applied_settings)
  end
end
