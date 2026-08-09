class AddCategoryEvidenceToSyncRunItems < ActiveRecord::Migration[8.1]
  def change
    add_column :sync_run_items, :category_evidence, :json
  end
end
