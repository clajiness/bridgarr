class NormalizeIndexerAppAssignmentSettings < ActiveRecord::Migration[8.1]
  def change
    unless column_exists?(:indexer_apps, :category_mode)
      add_column :indexer_apps, :category_mode, :string, default: "auto", null: false
    end

    add_column :indexer_apps, :custom_categories, :text unless column_exists?(:indexer_apps, :custom_categories)
    remove_column :indexer_apps, :category_override, :text if column_exists?(:indexer_apps, :category_override)
  end
end
