class AddSourceToJackettCategoryCatalog < ActiveRecord::Migration[8.1]
  def change
    add_column :indexers, :jackett_category_catalog_source, :string
  end
end
