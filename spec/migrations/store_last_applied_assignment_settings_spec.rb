require "rails_helper"
require Rails.root.join("db/migrate/20260807150000_store_last_applied_assignment_settings")

RSpec.describe StoreLastAppliedAssignmentSettings do
  subject(:migration) { described_class.new }

  before do
    IndexerApp.update_all(last_applied_settings: nil)
  end

  it "baselines only assignments whose current desired settings are known to be applied" do
    arr_app = ArrApp.create!(
      name: "Sonarr",
      app_type: "sonarr",
      base_url: "http://sonarr:8989",
      api_key: "key"
    )
    healthy_indexer = Indexer.create!(name: "Healthy", jackett_id: "healthy")
    pending_indexer = Indexer.create!(name: "Pending", jackett_id: "pending")
    failed_indexer = Indexer.create!(name: "Failed", jackett_id: "failed")
    healthy = IndexerApp.create!(
      arr_app:,
      indexer: healthy_indexer,
      connection_mode: "bridged",
      category_mode: "custom",
      custom_categories: "5000,5030",
      last_status: "ok",
      last_plan_state: "unchanged",
      last_applied_at: 1.hour.ago
    )
    pending = IndexerApp.create!(
      arr_app:,
      indexer: pending_indexer,
      category_mode: "none",
      last_status: "ok",
      last_plan_state: "update",
      last_applied_at: 1.hour.ago
    )
    failed = IndexerApp.create!(
      arr_app:,
      indexer: failed_indexer,
      last_status: "error",
      last_plan_state: "unchanged",
      last_applied_at: 1.hour.ago
    )

    migration.migrate(:up)

    expect(healthy.reload.last_applied_settings).to eq(healthy.desired_settings_snapshot)
    expect(pending.reload.last_applied_settings).to be_nil
    expect(failed.reload.last_applied_settings).to be_nil
  end
end
