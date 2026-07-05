class PreserveSyncRunItemsAfterAssignmentRemoval < ActiveRecord::Migration[8.1]
  def up
    add_column :sync_run_items, :indexer_name, :string
    add_column :sync_run_items, :arr_app_name, :string

    execute <<~SQL.squish
      UPDATE sync_run_items
      SET indexer_name = (
        SELECT indexers.name
        FROM indexer_apps
        INNER JOIN indexers ON indexers.id = indexer_apps.indexer_id
        WHERE indexer_apps.id = sync_run_items.indexer_app_id
      ),
      arr_app_name = (
        SELECT arr_apps.name
        FROM indexer_apps
        INNER JOIN arr_apps ON arr_apps.id = indexer_apps.arr_app_id
        WHERE indexer_apps.id = sync_run_items.indexer_app_id
      )
    SQL

    remove_foreign_key :sync_run_items, :indexer_apps
    change_column_null :sync_run_items, :indexer_app_id, true
    add_foreign_key :sync_run_items, :indexer_apps, on_delete: :nullify
  end

  def down
    remove_foreign_key :sync_run_items, :indexer_apps
    change_column_null :sync_run_items, :indexer_app_id, false
    add_foreign_key :sync_run_items, :indexer_apps

    remove_column :sync_run_items, :arr_app_name
    remove_column :sync_run_items, :indexer_name
  end
end
