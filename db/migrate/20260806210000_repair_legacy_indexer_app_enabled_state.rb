class RepairLegacyIndexerAppEnabledState < ActiveRecord::Migration[8.1]
  class MigrationIndexerApp < ActiveRecord::Base
    self.table_name = "indexer_apps"
  end

  def up
    say_with_time "Enabling legacy assignments whose desired state was never stored" do
      MigrationIndexerApp.unscoped.where(enabled: nil).update_all(enabled: true)
    end

    change_column_default :indexer_apps, :enabled, true unless enabled_column.default.in?([ true, "true", 1, "1" ])
    change_column_null :indexer_apps, :enabled, false if enabled_column.null
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "Legacy NULL assignment states cannot be distinguished after they are normalized."
  end

  private

    def enabled_column
      connection.columns(:indexer_apps).find { |column| column.name == "enabled" }
    end
end
