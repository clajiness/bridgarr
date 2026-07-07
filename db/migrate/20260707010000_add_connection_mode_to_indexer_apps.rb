class AddConnectionModeToIndexerApps < ActiveRecord::Migration[8.1]
  def change
    add_column :indexer_apps, :connection_mode, :string, null: false, default: "direct"
  end
end
