class AddReconciliationMetadata < ActiveRecord::Migration[8.1]
  def change
    change_table :indexer_apps, bulk: true do |t|
      t.string :last_plan_state
      t.datetime :last_inspected_at
      t.datetime :last_applied_at
      t.string :last_applied_digest
      t.string :last_desired_digest
      t.string :last_remote_digest
    end

    add_index :indexer_apps, :enabled
    add_index :indexer_apps, :last_plan_state

    change_table :sync_run_items, bulk: true do |t|
      t.string :planned_action
      t.string :plan_digest
      t.text :plan_changes
    end
  end
end
