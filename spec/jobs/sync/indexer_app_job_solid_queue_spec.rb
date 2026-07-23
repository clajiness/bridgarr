require "rails_helper"

RSpec.describe Sync::IndexerAppJob, type: :job do
  self.use_transactional_tests = false

  around do |example|
    ensure_solid_queue_schema!
    original_adapter = ActiveJob::Base.queue_adapter

    ActiveJob::Base.queue_adapter = :solid_queue
    clean_records
    example.run
  ensure
    clean_records
    ActiveJob::Base.queue_adapter = original_adapter
  end

  it "serializes jobs that validate the same Jackett indexer" do
    indexer = Indexer.create!(name: "1337x", jackett_id: "1337x")
    apps = %w[Radarr Sonarr Sonarr\ 4K].map do |name|
      ArrApp.create!(name:, app_type: name.start_with?("Radarr") ? "radarr" : "sonarr", base_url: "http://localhost", api_key: "#{name.parameterize}-key")
    end
    sync_run = SyncRun.create!(total_count: apps.size)
    items = apps.map do |arr_app|
      sync_run.sync_run_items.create!(indexer_app: IndexerApp.create!(arr_app:, indexer:))
    end
    live_order = []

    allow(Sync::IndexerAppSync).to receive(:call) do |indexer_app:|
      live_order << indexer_app.arr_app.name
      successful_result(indexer_app)
    end

    items.each { |item| described_class.perform_later(item.id) }

    expect(ready_indexer_executions.count).to eq(1)
    expect(blocked_indexer_executions.count).to eq(2)
    expect(blocked_indexer_executions.pluck(:concurrency_key).uniq).to eq([ "sync:indexer/indexer:#{indexer.id}" ])

    items.size.times { perform_next_ready_execution }

    expect(live_order).to eq(%w[Radarr Sonarr Sonarr\ 4K])
    expect(items.map { |item| item.reload.status }).to all(eq("succeeded"))
    expect(blocked_indexer_executions.count).to eq(0)
  end

  it "allows different Jackett indexers to be ready at the same time" do
    sonarr = ArrApp.create!(name: "Sonarr", app_type: "sonarr", base_url: "http://localhost:8989", api_key: "sonarr-key")
    radarr = ArrApp.create!(name: "Radarr", app_type: "radarr", base_url: "http://localhost:7878", api_key: "radarr-key")
    first_item = sync_item_for(indexer: Indexer.create!(name: "1337x", jackett_id: "1337x"), arr_app: sonarr)
    second_item = sync_item_for(indexer: Indexer.create!(name: "ExtraTorrent.st", jackett_id: "extratorrent-st"), arr_app: radarr)

    described_class.perform_later(first_item.id)
    described_class.perform_later(second_item.id)

    expect(ready_indexer_executions.count).to eq(2)
    expect(blocked_indexer_executions.count).to eq(0)
  end

  it "releases the indexer slot after an unexpected exception" do
    indexer = Indexer.create!(name: "1337x", jackett_id: "1337x")
    radarr = ArrApp.create!(name: "Radarr", app_type: "radarr", base_url: "http://localhost:7878", api_key: "radarr-key")
    sonarr = ArrApp.create!(name: "Sonarr", app_type: "sonarr", base_url: "http://localhost:8989", api_key: "sonarr-key")
    first_item = sync_item_for(indexer:, arr_app: radarr)
    second_item = sync_item_for(indexer:, arr_app: sonarr)

    call_count = 0
    allow(Sync::IndexerAppSync).to receive(:call) do |indexer_app:|
      call_count += 1
      raise StandardError, "unexpected validation failure" if call_count == 1

      successful_result(indexer_app)
    end

    described_class.perform_later(first_item.id)
    described_class.perform_later(second_item.id)

    perform_next_ready_execution

    expect(first_item.reload).to have_attributes(status: "failed", error_kind: "search_failed")
    expect(ready_indexer_executions.count).to eq(1)
    expect(blocked_indexer_executions.count).to eq(0)

    perform_next_ready_execution

    expect(second_item.reload.status).to eq("succeeded")
  end

  it "releases the indexer slot after a deterministic failure" do
    indexer = Indexer.create!(name: "LimeTorrents", jackett_id: "limetorrents")
    radarr = ArrApp.create!(name: "Radarr", app_type: "radarr", base_url: "http://localhost:7878", api_key: "radarr-key")
    sonarr = ArrApp.create!(name: "Sonarr", app_type: "sonarr", base_url: "http://localhost:8989", api_key: "sonarr-key")
    first_item = sync_item_for(indexer:, arr_app: radarr)
    second_item = sync_item_for(indexer:, arr_app: sonarr)

    allow(Sync::IndexerAppSync).to receive(:call).and_return(
      failed_result("Query successful, but no results in the configured categories were returned from your indexer."),
      successful_result(second_item.indexer_app)
    )

    described_class.perform_later(first_item.id)
    described_class.perform_later(second_item.id)

    perform_next_ready_execution

    expect(first_item.reload).to have_attributes(status: "mismatched", error_kind: "category_mismatch")
    expect(ready_indexer_executions.count).to eq(1)
    expect(blocked_indexer_executions.count).to eq(0)

    perform_next_ready_execution

    expect(second_item.reload.status).to eq("succeeded")
  end

  it "blocks a retry behind active work for the same Jackett indexer" do
    indexer = Indexer.create!(name: "ExtraTorrent.st", jackett_id: "extratorrent-st")
    radarr = ArrApp.create!(name: "Radarr", app_type: "radarr", base_url: "http://localhost:7878", api_key: "radarr-key")
    sonarr = ArrApp.create!(name: "Sonarr", app_type: "sonarr", base_url: "http://localhost:8989", api_key: "sonarr-key")
    active_item = sync_item_for(indexer:, arr_app: radarr)
    retry_item = sync_item_for(indexer:, arr_app: sonarr)
    retry_item.update!(
      status: "retrying",
      attempt_count: 1,
      next_retry_at: 5.seconds.ago,
      error: "Could not connect to Sonarr: Net::ReadTimeout",
      error_kind: "timeout",
      retryable: true
    )

    allow(Sync::IndexerAppSync).to receive(:call).and_return(
      successful_result(active_item.indexer_app),
      successful_result(retry_item.indexer_app)
    )

    described_class.perform_later(active_item.id)
    process, claimed_execution = claim_next_ready_execution

    described_class.perform_later(retry_item.id)

    expect(blocked_indexer_executions.count).to eq(1)
    expect(blocked_indexer_executions.first.concurrency_key).to eq("sync:indexer/indexer:#{indexer.id}")

    claimed_execution.perform
    process.destroy!

    expect(active_item.reload.status).to eq("succeeded")
    expect(ready_indexer_executions.count).to eq(1)
    expect(blocked_indexer_executions.count).to eq(0)

    perform_next_ready_execution

    expect(retry_item.reload.status).to eq("succeeded")
  end

  it "does not hold the indexer slot while a retry is delayed" do
    indexer = Indexer.create!(name: "ExtraTorrent.st", jackett_id: "extratorrent-st")
    radarr = ArrApp.create!(name: "Radarr", app_type: "radarr", base_url: "http://localhost:7878", api_key: "radarr-key")
    sonarr = ArrApp.create!(name: "Sonarr", app_type: "sonarr", base_url: "http://localhost:8989", api_key: "sonarr-key")
    first_item = sync_item_for(indexer:, arr_app: radarr)
    second_item = sync_item_for(indexer:, arr_app: sonarr)

    allow(Sync::IndexerAppSync).to receive(:call).and_return(
      failed_result("Could not connect to Radarr: Net::ReadTimeout with #<TCPSocket:(closed)>"),
      successful_result(second_item.indexer_app)
    )

    described_class.perform_later(first_item.id)
    described_class.perform_later(second_item.id)

    perform_next_ready_execution

    expect(first_item.reload).to have_attributes(status: "retrying", attempt_count: 1, error_kind: "timeout")
    expect(scheduled_indexer_executions.count).to eq(1)
    expect(ready_indexer_executions.count).to eq(1)
    expect(blocked_indexer_executions.count).to eq(0)

    perform_next_ready_execution

    expect(second_item.reload.status).to eq("succeeded")
  end

  private

    def ensure_solid_queue_schema!
      return if SolidQueue::Job.table_exists? &&
        SolidQueue::ReadyExecution.table_exists? &&
        SolidQueue::BlockedExecution.table_exists? &&
        SolidQueue::ScheduledExecution.table_exists?

      load Rails.root.join("db/queue_schema.rb")
    end

    def clean_records
      clean_solid_queue_records if SolidQueue::Job.table_exists?
      clean_application_records
    end

    def clean_solid_queue_records
      SolidQueue::Record.connection.disable_referential_integrity do
        SolidQueue::Record.descendants.each do |model|
          next if model.abstract_class? || !model.table_exists?

          model.delete_all
        end
      end
    end

    def clean_application_records
      ApplicationRecord.connection.disable_referential_integrity do
        ApplicationRecord.descendants.each do |model|
          next if model.abstract_class? || !model.table_exists?

          model.delete_all
        end
      end
    end

    def perform_next_ready_execution
      process, execution = claim_next_ready_execution

      execution.perform
    ensure
      process&.destroy! if process&.persisted?
    end

    def claim_next_ready_execution
      process = SolidQueue::Process.register(
        kind: "Worker",
        name: "solid-queue-spec-#{SecureRandom.hex(8)}",
        pid: Process.pid,
        hostname: "test",
        metadata: {}
      )
      ready_execution = ready_indexer_executions.order(:id).first

      expect(ready_execution).to be_present

      execution = SolidQueue::ClaimedExecution.claiming([ ready_execution.job_id ], process.id) do
        SolidQueue::ReadyExecution.where(id: ready_execution.id).delete_all
      end.first

      expect(execution).to be_present

      [ process, execution ]
    end

    def ready_indexer_executions
      SolidQueue::ReadyExecution.joins(:job).where(solid_queue_jobs: { class_name: described_class.name })
    end

    def blocked_indexer_executions
      SolidQueue::BlockedExecution.joins(:job).where(solid_queue_jobs: { class_name: described_class.name })
    end

    def scheduled_indexer_executions
      SolidQueue::ScheduledExecution.joins(:job).where(solid_queue_jobs: { class_name: described_class.name })
    end

    def sync_item_for(indexer:, arr_app:)
      sync_run = SyncRun.create!(total_count: 1)
      sync_run.sync_run_items.create!(indexer_app: IndexerApp.create!(indexer:, arr_app:))
    end

    def successful_result(indexer_app)
      Sync::IndexerAppSync::Result.new(
        success?: true,
        skipped?: false,
        remote_indexer_id: indexer_app.remote_indexer_id || indexer_app.id,
        message: "#{indexer_app.indexer.name} synced to #{indexer_app.arr_app.name}.",
        error: nil
      )
    end

    def failed_result(message)
      Sync::IndexerAppSync::Result.new(
        success?: false,
        skipped?: false,
        remote_indexer_id: nil,
        message:,
        error: message
      )
    end
end
