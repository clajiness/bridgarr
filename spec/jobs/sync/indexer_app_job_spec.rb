require "rails_helper"

RSpec.describe Sync::IndexerAppJob, type: :job do
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

  it "limits live sync work to one job per Jackett indexer" do
    indexer = Indexer.create!(name: "1337x", jackett_id: "1337x")
    sonarr = ArrApp.create!(name: "Sonarr", app_type: "sonarr", base_url: "http://localhost:8989", api_key: "sonarr-api-key")
    radarr = ArrApp.create!(name: "Radarr", app_type: "radarr", base_url: "http://localhost:7878", api_key: "radarr-api-key")
    other_indexer = Indexer.create!(name: "EZTV", jackett_id: "eztv")
    sync_run = SyncRun.create!(total_count: 3)

    first_item = sync_run.sync_run_items.create!(indexer_app: IndexerApp.create!(arr_app: sonarr, indexer:))
    second_item = sync_run.sync_run_items.create!(indexer_app: IndexerApp.create!(arr_app: radarr, indexer:))
    other_item = sync_run.sync_run_items.create!(indexer_app: IndexerApp.create!(arr_app: sonarr, indexer: other_indexer))

    expect(described_class.concurrency_limit).to eq(1)
    expect(described_class.concurrency_group).to eq("sync:indexer")
    expect(described_class.concurrency_on_conflict).to eq(:block)
    expect(described_class.indexer_concurrency_key(first_item.id)).to eq("indexer:#{indexer.id}")
    expect(described_class.indexer_concurrency_key(second_item.id)).to eq("indexer:#{indexer.id}")
    expect(described_class.indexer_concurrency_key(other_item.id)).to eq("indexer:#{other_indexer.id}")
    expect(described_class.new(first_item.id).concurrency_key).to eq("sync:indexer/indexer:#{indexer.id}")
  end

  it "syncs an assignment and updates the sync run item" do
    arr_app = ArrApp.create!(name: "Sonarr", app_type: "sonarr", base_url: "http://localhost:8989", api_key: "sonarr-api-key")
    indexer = Indexer.create!(name: "EZTV", jackett_id: "eztv")
    indexer_app = IndexerApp.create!(arr_app:, indexer:)
    sync_run = SyncRun.create!(total_count: 1)
    sync_run_item = sync_run.sync_run_items.create!(indexer_app:)
    result = Sync::IndexerAppSync::Result.new(
      success?: true,
      remote_indexer_id: 42,
      message: "EZTV synced to Sonarr.",
      error: nil
    )
    allow(Sync::IndexerAppSync).to receive(:call).and_return(result)

    described_class.perform_now(sync_run_item.id)

    expect(Sync::IndexerAppSync).to have_received(:call).with(indexer_app:)
    expect(sync_run_item.reload).to have_attributes(status: "succeeded", error: nil)
    expect(sync_run.reload).to have_attributes(status: "succeeded", success_count: 1, failure_count: 0, skipped_count: 0)
  end

  it "fails the item when the assignment was removed before the job runs" do
    arr_app = ArrApp.create!(name: "Sonarr", app_type: "sonarr", base_url: "http://localhost:8989", api_key: "sonarr-api-key")
    indexer = Indexer.create!(name: "EZTV", jackett_id: "eztv")
    indexer_app = IndexerApp.create!(arr_app:, indexer:)
    sync_run = SyncRun.create!(total_count: 1)
    sync_run_item = sync_run.sync_run_items.create!(indexer_app:, indexer_name: "EZTV", arr_app_name: "Sonarr")
    indexer_app.destroy!

    described_class.perform_now(sync_run_item.id)

    expect(sync_run_item.reload).to have_attributes(status: "failed", error: "Assignment was removed before sync.")
    expect(sync_run.reload).to have_attributes(status: "failed", success_count: 0, failure_count: 1, skipped_count: 0)
  end

  it "marks skipped assignments without failing the sync run" do
    arr_app = ArrApp.create!(name: "Radarr", app_type: "radarr", base_url: "http://localhost:7878", api_key: "radarr-api-key")
    indexer = Indexer.create!(name: "EZTV", jackett_id: "eztv")
    indexer_app = IndexerApp.create!(arr_app:, indexer:)
    sync_run = SyncRun.create!(total_count: 1)
    sync_run_item = sync_run.sync_run_items.create!(indexer_app:)
    result = Sync::IndexerAppSync::Result.new(
      success?: false,
      skipped?: true,
      remote_indexer_id: nil,
      message: "EZTV does not expose Radarr-compatible Torznab categories.",
      error: "EZTV does not expose Radarr-compatible Torznab categories."
    )
    allow(Sync::IndexerAppSync).to receive(:call).and_return(result)

    described_class.perform_now(sync_run_item.id)

    expect(sync_run_item.reload).to have_attributes(
      status: "skipped",
      error: "EZTV does not expose Radarr-compatible Torznab categories.",
      error_kind: "incompatible_categories",
      retryable: false
    )
    expect(sync_run.reload).to have_attributes(status: "skipped", success_count: 0, failure_count: 0, skipped_count: 1)
  end

  it "redacts and classifies exception messages before storing them" do
    arr_app = ArrApp.create!(name: "Sonarr", app_type: "sonarr", base_url: "http://localhost:8989", api_key: "sonarr-api-key")
    indexer = Indexer.create!(name: "1337x", jackett_id: "1337x")
    indexer_app = IndexerApp.create!(arr_app:, indexer:)
    sync_run = SyncRun.create!(total_count: 1)
    sync_run_item = sync_run.sync_run_items.create!(indexer_app:)
    allow(Sync::IndexerAppSync).to receive(:call).and_raise(
      Faraday::TimeoutError,
      "GET http://localhost:9117/api?t=tvsearch&apikey=super-secret-key timed out"
    )

    described_class.perform_now(sync_run_item.id)

    expect(sync_run_item.reload).to have_attributes(status: "retrying", attempt_count: 1, error_kind: "timeout")
    expect(sync_run_item.error).to include("apikey=[REDACTED]")
    expect(sync_run_item.error).not_to include("super-secret-key")
    expect(sync_run_item).to be_retryable
    expect(sync_run.reload.status).to eq("running")
    expect(enqueued_indexer_app_jobs).to include(a_hash_including(job: described_class))
  end

  it "schedules one delayed retry for a transient result failure and then succeeds" do
    arr_app = ArrApp.create!(name: "Sonarr", app_type: "sonarr", base_url: "http://localhost:8989", api_key: "sonarr-api-key")
    indexer = Indexer.create!(name: "1337x", jackett_id: "1337x")
    indexer_app = IndexerApp.create!(arr_app:, indexer:)
    sync_run = SyncRun.create!(total_count: 1)
    sync_run_item = sync_run.sync_run_items.create!(indexer_app:)
    timeout = Sync::IndexerAppSync::Result.new(
      success?: false,
      skipped?: false,
      remote_indexer_id: nil,
      message: "Could not connect to Sonarr: Net::ReadTimeout with #<TCPSocket:(closed)>",
      error: "Could not connect to Sonarr: Net::ReadTimeout with #<TCPSocket:(closed)>"
    )
    success = Sync::IndexerAppSync::Result.new(
      success?: true,
      skipped?: false,
      remote_indexer_id: 42,
      message: "1337x synced to Sonarr.",
      error: nil
    )
    allow(Sync::IndexerAppSync).to receive(:call).and_return(timeout, success)

    described_class.perform_now(sync_run_item.id)

    expect(sync_run_item.reload).to have_attributes(status: "retrying", attempt_count: 1, error_kind: "timeout", retryable: true)
    expect(sync_run_item.next_retry_at).to be_present
    expect(sync_run.reload.status).to eq("running")
    expect(enqueued_indexer_app_jobs).to include(a_hash_including(job: described_class))

    clear_enqueued_jobs
    described_class.perform_now(sync_run_item.id)

    expect(sync_run_item.reload).to have_attributes(status: "succeeded", attempt_count: 2, error: nil, next_retry_at: nil)
    expect(sync_run.reload).to have_attributes(status: "succeeded", success_count: 1, failure_count: 0)
    expect(enqueued_indexer_app_jobs).to be_empty
  end

  it "fails after the final retryable attempt without scheduling a third attempt" do
    arr_app = ArrApp.create!(name: "Sonarr", app_type: "sonarr", base_url: "http://localhost:8989", api_key: "sonarr-api-key")
    indexer = Indexer.create!(name: "ExtraTorrent.st", jackett_id: "extratorrent-st")
    indexer_app = IndexerApp.create!(arr_app:, indexer:)
    sync_run = SyncRun.create!(total_count: 1)
    sync_run_item = sync_run.sync_run_items.create!(indexer_app:)
    allow(Sync::IndexerAppSync).to receive(:call).and_raise(Faraday::TimeoutError, "execution expired")

    described_class.perform_now(sync_run_item.id)
    clear_enqueued_jobs
    described_class.perform_now(sync_run_item.id)

    expect(sync_run_item.reload).to have_attributes(status: "failed", attempt_count: 2, error_kind: "timeout", retryable: true, next_retry_at: nil)
    expect(sync_run.reload).to have_attributes(status: "failed", success_count: 0, failure_count: 1)
    expect(enqueued_indexer_app_jobs).to be_empty
  end

  it "does not retry deterministic category failures" do
    arr_app = ArrApp.create!(name: "Radarr", app_type: "radarr", base_url: "http://localhost:7878", api_key: "radarr-api-key")
    indexer = Indexer.create!(name: "LimeTorrents", jackett_id: "limetorrents")
    indexer_app = IndexerApp.create!(arr_app:, indexer:)
    sync_run = SyncRun.create!(total_count: 1)
    sync_run_item = sync_run.sync_run_items.create!(indexer_app:)
    result = Sync::IndexerAppSync::Result.new(
      success?: false,
      skipped?: false,
      remote_indexer_id: nil,
      message: "Query successful, but no results in the configured categories were returned from your indexer.",
      error: "Query successful, but no results in the configured categories were returned from your indexer."
    )
    allow(Sync::IndexerAppSync).to receive(:call).and_return(result)

    described_class.perform_now(sync_run_item.id)

    expect(sync_run_item.reload).to have_attributes(status: "mismatched", attempt_count: 1, error_kind: "category_mismatch", retryable: false)
    expect(sync_run.reload).to have_attributes(status: "mismatched", failure_count: 0, mismatch_count: 1)
    expect(enqueued_indexer_app_jobs).to be_empty
  end

  it "does not retry authentication failures" do
    arr_app = ArrApp.create!(name: "Radarr", app_type: "radarr", base_url: "http://localhost:7878", api_key: "radarr-api-key")
    indexer = Indexer.create!(name: "LimeTorrents", jackett_id: "limetorrents")
    indexer_app = IndexerApp.create!(arr_app:, indexer:)
    sync_run = SyncRun.create!(total_count: 1)
    sync_run_item = sync_run.sync_run_items.create!(indexer_app:)
    result = Sync::IndexerAppSync::Result.new(
      success?: false,
      skipped?: false,
      remote_indexer_id: nil,
      message: "Radarr returned HTTP 401 Unauthorized.",
      error: "Radarr returned HTTP 401 Unauthorized."
    )
    allow(Sync::IndexerAppSync).to receive(:call).and_return(result)

    described_class.perform_now(sync_run_item.id)

    expect(sync_run_item.reload).to have_attributes(status: "failed", attempt_count: 1, error_kind: "authentication", retryable: false)
    expect(sync_run.reload).to have_attributes(status: "failed", failure_count: 1)
    expect(enqueued_indexer_app_jobs).to be_empty
  end

  it "ignores duplicate jobs after an assignment already reached a terminal state" do
    arr_app = ArrApp.create!(name: "Sonarr", app_type: "sonarr", base_url: "http://localhost:8989", api_key: "sonarr-api-key")
    indexer = Indexer.create!(name: "1337x", jackett_id: "1337x")
    indexer_app = IndexerApp.create!(arr_app:, indexer:)
    sync_run = SyncRun.create!(total_count: 1)
    sync_run_item = sync_run.sync_run_items.create!(indexer_app:)
    success = Sync::IndexerAppSync::Result.new(
      success?: true,
      skipped?: false,
      remote_indexer_id: 42,
      message: "1337x synced to Sonarr.",
      error: nil
    )
    allow(Sync::IndexerAppSync).to receive(:call) do
      indexer_app.update!(remote_indexer_id: 42)
      success
    end

    described_class.perform_now(sync_run_item.id)
    described_class.perform_now(sync_run_item.id)

    expect(Sync::IndexerAppSync).to have_received(:call).once
    expect(sync_run_item.reload).to have_attributes(status: "succeeded", attempt_count: 1)
    expect(indexer_app.reload.remote_indexer_id).to eq(42)
  end

  it "ignores abandoned retry jobs" do
    arr_app = ArrApp.create!(name: "Sonarr", app_type: "sonarr", base_url: "http://localhost:8989", api_key: "sonarr-api-key")
    indexer = Indexer.create!(name: "1337x", jackett_id: "1337x")
    indexer_app = IndexerApp.create!(arr_app:, indexer:)
    sync_run = SyncRun.create!(status: "failed", total_count: 1)
    sync_run_item = sync_run.sync_run_items.create!(indexer_app:, status: "failed", error: "Sync run was abandoned.")
    allow(Sync::IndexerAppSync).to receive(:call)

    described_class.perform_now(sync_run_item.id)

    expect(Sync::IndexerAppSync).not_to have_received(:call)
    expect(sync_run_item.reload.attempt_count).to eq(0)
  end

  def enqueued_indexer_app_jobs
    enqueued_jobs.select { |job| job[:job] == described_class }
  end
end
