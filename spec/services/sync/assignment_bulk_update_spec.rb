require "rails_helper"

RSpec.describe Sync::AssignmentBulkUpdate do
  let(:arr_app) do
    ArrApp.create!(name: "Sonarr", app_type: "sonarr", base_url: "http://localhost:8989", api_key: "key")
  end

  let(:indexer) { Indexer.create!(name: "EZTV", jackett_id: "eztv") }

  it "creates a selected assignment with every search mode enabled and in direct mode" do
    result = described_class.call(cells: [ [ indexer.id, arr_app.id ] ], action: "create")

    assignment = IndexerApp.find_by!(indexer:, arr_app:)
    expect(result).to be_success
    expect(result.changed_count).to eq(1)
    expect(assignment).to be_all_search_modes_enabled
    expect(assignment).to be_connection_mode_direct
  end

  it "skips cells that already have assignments during create" do
    assignment = IndexerApp.create!(indexer:, arr_app:)

    result = described_class.call(cells: [ [ indexer.id, arr_app.id ] ], action: "create")

    expect(result).to be_success
    expect(result.changed_count).to eq(0)
    expect(result.message).to include("No assignments were created", "already assigned")
    expect(IndexerApp.where(id: assignment.id)).to exist
  end

  it "updates desired state for existing assignments" do
    assignment = IndexerApp.create!(indexer:, arr_app:)

    result = described_class.call(
      cells: [ [ indexer.id, arr_app.id ] ],
      action: "categories",
      category_mode: "custom",
      custom_categories: "2000, 8000"
    )

    expect(result).to be_success
    expect(assignment.reload).to have_attributes(category_mode: "custom", custom_categories: "2000,8000")
  end

  it "rolls back bulk desired-state changes when a selected assignment is actively syncing" do
    active_assignment = IndexerApp.create!(indexer:, arr_app:)
    other_indexer = Indexer.create!(name: "1337x", jackett_id: "1337x")
    other_assignment = IndexerApp.create!(indexer: other_indexer, arr_app:)
    sync_run = SyncRun.create!(status: "running", total_count: 1)
    sync_run.sync_run_items.create!(indexer_app: active_assignment, status: "running")

    result = described_class.call(
      cells: [ [ other_indexer.id, arr_app.id ], [ indexer.id, arr_app.id ] ],
      action: "search_modes",
      enable_rss: "disable"
    )

    expect(result).not_to be_success
    expect(result.message).to include("active assignment sync")
    expect(active_assignment.reload).to be_enable_rss
    expect(other_assignment.reload).to be_enable_rss
  end

  it "updates selected search modes while keeping the others unchanged" do
    assignment = IndexerApp.create!(indexer:, arr_app:, enable_interactive_search: false)

    result = described_class.call(
      cells: [ [ indexer.id, arr_app.id ] ],
      action: "search_modes",
      enable_rss: "disable",
      enable_automatic_search: "keep",
      enable_interactive_search: "enable"
    )

    expect(result).to be_success
    expect(assignment.reload).to have_attributes(
      enable_rss: false,
      enable_automatic_search: true,
      enable_interactive_search: true
    )
  end

  it "requires at least one search-mode change" do
    assignment = IndexerApp.create!(indexer:, arr_app:)

    result = described_class.call(
      cells: [ [ indexer.id, arr_app.id ] ],
      action: "search_modes",
      enable_rss: "keep",
      enable_automatic_search: "keep",
      enable_interactive_search: "keep"
    )

    expect(result).not_to be_success
    expect(result.message).to include("at least one search mode")
    expect(assignment.reload).to be_all_search_modes_enabled
  end

  it "rejects setting updates when every selected cell is unassigned" do
    result = described_class.call(
      cells: [ [ indexer.id, arr_app.id ] ],
      action: "search_modes",
      enable_rss: "disable"
    )

    expect(result).not_to be_success
    expect(result.message).to include("do not have assignments yet")
  end

  it "rolls back every cell when one selected assignment is invalid" do
    result = described_class.call(
      cells: [ [ indexer.id, arr_app.id ], [ indexer.id, 999_999 ] ],
      action: "create"
    )

    expect(result).not_to be_success
    expect(IndexerApp.count).to eq(0)
  end

  it "rejects unknown actions" do
    result = described_class.call(cells: [ [ indexer.id, arr_app.id ] ], action: "unknown")

    expect(result).not_to be_success
    expect(result.message).to eq("Choose a valid bulk action.")
    expect(IndexerApp.count).to eq(0)
  end

  it "returns a refreshable failure when the matrix changes during persistence" do
    allow_any_instance_of(IndexerApp).to receive(:update!).and_raise(ActiveRecord::InvalidForeignKey)

    result = described_class.call(cells: [ [ indexer.id, arr_app.id ] ], action: "create")

    expect(result).not_to be_success
    expect(result.message).to include("matrix changed", "Refresh")
  end
end
