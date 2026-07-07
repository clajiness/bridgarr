class AddCategorySettingsToIndexerApps < ActiveRecord::Migration[8.1]
  def change
    add_column :indexer_apps, :category_mode, :string, default: "auto", null: false
    add_column :indexer_apps, :custom_categories, :text
  end
end
