class ReplaceAssignmentEnabledWithSearchModes < ActiveRecord::Migration[8.1]
  def up
    add_column :indexer_apps, :enable_rss, :boolean, null: false, default: true
    add_column :indexer_apps, :enable_automatic_search, :boolean, null: false, default: true
    add_column :indexer_apps, :enable_interactive_search, :boolean, null: false, default: true

    execute <<~SQL.squish
      UPDATE indexer_apps
      SET enable_rss = enabled,
          enable_automatic_search = enabled,
          enable_interactive_search = enabled
    SQL

    remove_index :indexer_apps, :enabled if index_exists?(:indexer_apps, :enabled)
    remove_column :indexer_apps, :enabled
  end

  def down
    add_column :indexer_apps, :enabled, :boolean, null: false, default: true

    execute <<~SQL.squish
      UPDATE indexer_apps
      SET enabled = CASE
        WHEN enable_rss = FALSE AND enable_automatic_search = FALSE AND enable_interactive_search = FALSE THEN FALSE
        ELSE TRUE
      END
    SQL

    remove_column :indexer_apps, :enable_rss
    remove_column :indexer_apps, :enable_automatic_search
    remove_column :indexer_apps, :enable_interactive_search
    add_index :indexer_apps, :enabled
  end
end
