require "rails_helper"

RSpec.describe Sync::BulkSync do
  include ActiveJob::TestHelper

  around do |example|
    original_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
    clear_performed_jobs
    example.run
  ensure
    clear_enqueued_jobs
    clear_performed_jobs
    ActiveJob::Base.queue_adapter = original_adapter
  end

  it "creates a sync run with enabled assignments and enqueues the coordinator job" do
    enabled_assignment = create_assignment(indexer_name: "EZTV", arr_app_name: "Sonarr")
    disabled_assignment = create_assignment(indexer_name: "Disabled", arr_app_name: "Radarr", indexer_enabled: false)
    hidden_disabled_assignment = create_assignment(indexer_name: "Hidden Disabled", arr_app_name: "Sonarr 4K", assignment_enabled: false)

    sync_run = described_class.call

    expect(sync_run).to be_persisted
    expect(sync_run.total_count).to eq(2)
    expect(sync_run.sync_run_items.pluck(:indexer_app_id)).to contain_exactly(enabled_assignment.id, hidden_disabled_assignment.id)
    expect(sync_run.sync_run_items.pluck(:indexer_app_id)).not_to include(disabled_assignment.id)
    expect(Sync::BulkSyncJob).to have_been_enqueued.with(sync_run.id)
  end

  def create_assignment(indexer_name:, arr_app_name:, indexer_enabled: true, assignment_enabled: true)
    arr_app = ArrApp.create!(
      name: arr_app_name,
      app_type: "sonarr",
      base_url: "http://localhost:8989",
      api_key: "sonarr-api-key",
      enabled: true
    )
    indexer = Indexer.create!(name: indexer_name, jackett_id: indexer_name.parameterize, enabled: indexer_enabled)

    IndexerApp.create!(arr_app:, indexer:, enabled: assignment_enabled)
  end
end
