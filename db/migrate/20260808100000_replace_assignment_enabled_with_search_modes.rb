class ReplaceAssignmentEnabledWithSearchModes < ActiveRecord::Migration[8.1]
  SEARCH_MODE_KEYS = %w[enable_rss enable_automatic_search enable_interactive_search].freeze

  class MigrationIndexerApp < ActiveRecord::Base
    self.table_name = "indexer_apps"
  end

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

    migrate_snapshots_up
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

    migrate_snapshots_down
    remove_column :indexer_apps, :enable_rss
    remove_column :indexer_apps, :enable_automatic_search
    remove_column :indexer_apps, :enable_interactive_search
    add_index :indexer_apps, :enabled
  end

  private

    def migrate_snapshots_up
      each_snapshot do |assignment, snapshot|
        next unless snapshot["enabled"].in?([ true, false ])
        next if SEARCH_MODE_KEYS.any? { |key| snapshot.key?(key) }

        enabled = snapshot.delete("enabled")
        assignment.update_columns(last_applied_settings: snapshot.merge(SEARCH_MODE_KEYS.index_with { enabled }))
      end
    end

    def migrate_snapshots_down
      each_snapshot do |assignment, snapshot|
        next unless SEARCH_MODE_KEYS.all? { |key| snapshot[key].in?([ true, false ]) }

        enabled = SEARCH_MODE_KEYS.any? { |key| snapshot[key] }
        snapshot.except!(*SEARCH_MODE_KEYS)
        assignment.update_columns(last_applied_settings: snapshot.merge("enabled" => enabled))
      end
    end

    def each_snapshot
      return unless column_exists?(:indexer_apps, :last_applied_settings)

      MigrationIndexerApp.reset_column_information
      MigrationIndexerApp.where.not(last_applied_settings: nil).find_each do |assignment|
        snapshot = assignment.last_applied_settings
        yield assignment, snapshot.stringify_keys if snapshot.is_a?(Hash)
      end
    end
end
