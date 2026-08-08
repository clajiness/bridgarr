require "rails_helper"

RSpec.describe "Live refresh broadcasts", type: :model do
  it "refreshes dashboard, readiness, health, indexer, and matrix views when an indexer changes" do
    indexer = Indexer.create!(name: "1337x", jackett_id: "1337x")
    allow(indexer).to receive(:broadcast_refresh_later_to)

    indexer.update!(last_status: "ok")

    %w[dashboard readiness health indexers assignment_matrix].each do |stream|
      expect(indexer).to have_received(:broadcast_refresh_later_to).with(stream)
    end
    expect(indexer).not_to have_received(:broadcast_refresh_later_to).with("arr_apps")
  end

  it "refreshes app assignment references when an indexer name or Jackett ID changes" do
    indexer = Indexer.create!(name: "1337x", jackett_id: "1337x")
    allow(indexer).to receive(:broadcast_refresh_later_to)

    indexer.update!(name: "1337x renamed")

    expect(indexer).to have_received(:broadcast_refresh_later_to).with("arr_apps")
  end

  it "refreshes dashboard, readiness, health, and app views when app health changes" do
    arr_app = ArrApp.create!(name: "Sonarr", app_type: "sonarr", base_url: "http://sonarr:8989", api_key: "key")
    allow(arr_app).to receive(:broadcast_refresh_later_to)

    arr_app.update!(last_status: "ok")

    %w[dashboard readiness health arr_apps].each do |stream|
      expect(arr_app).to have_received(:broadcast_refresh_later_to).with(stream)
    end
    expect(arr_app).not_to have_received(:broadcast_refresh_later_to).with("indexers")
    expect(arr_app).not_to have_received(:broadcast_refresh_later_to).with("assignment_matrix")
  end

  it "refreshes indexer and matrix references when relevant app fields change" do
    arr_app = ArrApp.create!(name: "Sonarr", app_type: "sonarr", base_url: "http://sonarr:8989", api_key: "key")
    allow(arr_app).to receive(:broadcast_refresh_later_to)

    arr_app.update!(name: "Sonarr HD")

    expect(arr_app).to have_received(:broadcast_refresh_later_to).with("indexers")
    expect(arr_app).to have_received(:broadcast_refresh_later_to).with("assignment_matrix")
  end

  it "refreshes dashboard, readiness, matrix, indexer, and app views when an assignment changes" do
    arr_app = ArrApp.create!(name: "Sonarr", app_type: "sonarr", base_url: "http://sonarr:8989", api_key: "key")
    indexer = Indexer.create!(name: "1337x", jackett_id: "1337x")
    assignment = IndexerApp.create!(arr_app:, indexer:)
    allow(assignment).to receive(:broadcast_refresh_later_to)

    assignment.update!(last_status: "ok")

    expect(assignment).to have_received(:broadcast_refresh_later_to).with("dashboard")
    expect(assignment).to have_received(:broadcast_refresh_later_to).with("readiness")
    expect(assignment).to have_received(:broadcast_refresh_later_to).with("assignment_matrix")
    expect(assignment).to have_received(:broadcast_refresh_later_to).with("indexers")
    expect(assignment).to have_received(:broadcast_refresh_later_to).with("arr_apps")
  end

  it "refreshes dashboard and sync history when a sync run changes" do
    sync_run = SyncRun.create!
    allow(sync_run).to receive(:broadcast_refresh_later_to)
    allow(sync_run).to receive(:broadcast_replace_later_to)

    sync_run.update!(status: "running", started_at: Time.current)

    expect(sync_run).to have_received(:broadcast_refresh_later_to).with("dashboard")
    expect(sync_run).to have_received(:broadcast_refresh_later_to).with("sync_runs")
    expect(sync_run).to have_received(:broadcast_replace_later_to).with(sync_run, attributes: { method: :morph })
  end

  it "refreshes assignment surfaces when a sync item is created or changes status" do
    arr_app = ArrApp.create!(name: "Sonarr", app_type: "sonarr", base_url: "http://sonarr:8989", api_key: "key")
    indexer = Indexer.create!(name: "1337x", jackett_id: "1337x")
    assignment = IndexerApp.create!(arr_app:, indexer:)
    sync_run = SyncRun.create!
    sync_run_item = SyncRunItem.new(
      sync_run:,
      indexer_app: assignment,
      indexer_name: indexer.name,
      arr_app_name: arr_app.name
    )
    allow(sync_run_item).to receive(:broadcast_refresh_later_to)
    allow(sync_run_item).to receive(:broadcast_replace_later_to)

    sync_run_item.save!
    sync_run_item.update!(status: "running")
    sync_run_item.update!(plan_changes: "[]")

    %w[dashboard indexers arr_apps].each do |stream|
      expect(sync_run_item).to have_received(:broadcast_refresh_later_to).with(stream).twice
    end
    expect(sync_run_item).to have_received(:broadcast_replace_later_to)
      .with(sync_run, attributes: { method: :morph }).twice
  end

  it "refreshes health and dashboard views when settings-backed health changes" do
    setting = Setting.create!(key: Setting::JACKETT_LAST_STATUS_KEY, value: "unknown")
    allow(setting).to receive(:broadcast_refresh_later_to)

    setting.update!(value: "ok")

    expect(setting).to have_received(:broadcast_refresh_later_to).with("dashboard")
    expect(setting).to have_received(:broadcast_refresh_later_to).with("readiness")
    expect(setting).to have_received(:broadcast_refresh_later_to).with("health")
    expect(setting).not_to have_received(:broadcast_refresh_later_to).with("assignment_matrix")
  end

  it "refreshes the assignment matrix when an API key version changes" do
    setting = Setting.create!(key: Setting::JACKETT_API_KEY_VERSION_KEY, value: "1")
    allow(setting).to receive(:broadcast_refresh_later_to)

    setting.update!(value: "2")

    expect(setting).to have_received(:broadcast_refresh_later_to).with("assignment_matrix")
    expect(setting).not_to have_received(:broadcast_refresh_later_to).with("readiness")
    expect(setting).not_to have_received(:broadcast_refresh_later_to).with("health")
  end

  it "refreshes the dashboard for failed proxy requests but not successful traffic" do
    failed_request = ProxyRequest.new(jackett_id: "1337x", request_type: "search", http_status: 500, duration_ms: 50)
    allow(failed_request).to receive(:broadcast_refresh_later_to)
    failed_request.save!
    failed_request.destroy!

    successful_request = ProxyRequest.new(jackett_id: "1337x", request_type: "search", http_status: 200, duration_ms: 50)
    allow(successful_request).to receive(:broadcast_refresh_later_to)
    successful_request.save!

    expect(failed_request).to have_received(:broadcast_refresh_later_to).with("dashboard").twice
    expect(successful_request).not_to have_received(:broadcast_refresh_later_to)
  end
end
