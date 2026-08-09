class AddJackettCategoryCatalogToIndexers < ActiveRecord::Migration[8.1]
  def change
    add_column :indexers, :jackett_category_catalog, :json
    add_column :indexers, :jackett_category_catalog_refreshed_at, :datetime
  end
end
