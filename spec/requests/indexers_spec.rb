require "rails_helper"

RSpec.describe "Indexers", type: :request do
  let(:arr_app) do
    ArrApp.create!(
      name: "Main Sonarr",
      app_type: "sonarr",
      base_url: "http://localhost:8989",
      api_key: "sonarr-api-key"
    )
  end

  let(:indexer) do
    Indexer.create!(name: "First Indexer", jackett_id: "first-indexer", arr_app_ids: [ arr_app.id ])
  end

  it "renders the indexers index" do
    indexer

    get indexers_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("First Indexer")
    expect(response.body).to include("Discover from Jackett")
  end

  it "renders the empty indexers state" do
    get indexers_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Add your first Jackett indexer and let Bridgarr tie the stack together.")
    expect(response.body).to include("Discover from Jackett")
  end

  it "previews configured Jackett indexers for import" do
    Setting.write_value(Setting::JACKETT_BASE_URL_KEY, "http://localhost:9117")
    Setting.write_value(Setting::JACKETT_API_KEY_KEY, "jackett-api-key")
    Indexer.create!(name: "Existing Indexer", jackett_id: "existing-indexer")

    result = Jackett::IndexerDiscovery::Result.new(
      success?: true,
      indexers: [
        Jackett::IndexerDiscovery::IndexerRecord.new(name: "Existing Indexer", jackett_id: "existing-indexer", configured: true),
        Jackett::IndexerDiscovery::IndexerRecord.new(name: "New Indexer", jackett_id: "new-indexer", configured: true)
      ],
      message: "Found 2 configured Jackett indexers.",
      error: nil,
      http_status: 200
    )
    allow(Jackett::IndexerDiscovery).to receive(:call).and_return(result)

    get discover_indexers_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Existing Indexer")
    expect(response.body).to include("Already imported")
    expect(response.body).to include("New Indexer")
    expect(response.body).to include("Ready to import")
    expect(response.body).to include("Import selected indexers")
    expect(response.body).to include("jackett_ids[]")
  end

  it "redirects when Jackett indexer discovery fails" do
    result = Jackett::IndexerDiscovery::Result.new(
      success?: false,
      indexers: [],
      message: "Add a Jackett URL before discovering indexers.",
      error: "Add a Jackett URL before discovering indexers.",
      http_status: nil
    )
    allow(Jackett::IndexerDiscovery).to receive(:call).and_return(result)

    get discover_indexers_path

    expect(response).to redirect_to(indexers_path)
    expect(flash[:alert]).to eq("Add a Jackett URL before discovering indexers.")
  end

  it "imports missing Jackett indexers" do
    Setting.write_value(Setting::JACKETT_BASE_URL_KEY, "http://localhost:9117")
    Setting.write_value(Setting::JACKETT_API_KEY_KEY, "jackett-api-key")

    result = Jackett::IndexerImport::Result.new(
      success?: true,
      imported_count: 2,
      skipped_count: 1,
      message: "2 indexers imported, 1 already present.",
      error: nil
    )
    allow(Jackett::IndexerImport).to receive(:call).and_return(result)

    post import_from_jackett_indexers_path, params: { jackett_ids: [ "first-indexer", "second-indexer" ] }

    expect(response).to redirect_to(indexers_path)
    expect(Jackett::IndexerImport).to have_received(:call).with(
      base_url: "http://localhost:9117",
      api_key: "jackett-api-key",
      jackett_ids: [ "first-indexer", "second-indexer" ]
    )
    expect(flash[:notice]).to eq("2 indexers imported, 1 already present.")
  end

  it "redirects when Jackett indexer import fails" do
    result = Jackett::IndexerImport::Result.new(
      success?: false,
      imported_count: 0,
      skipped_count: 0,
      message: "Add a Jackett URL before discovering indexers.",
      error: "Add a Jackett URL before discovering indexers."
    )
    allow(Jackett::IndexerImport).to receive(:call).and_return(result)

    post import_from_jackett_indexers_path

    expect(response).to redirect_to(indexers_path)
    expect(flash[:alert]).to eq("Add a Jackett URL before discovering indexers.")
  end

  it "renders the new indexer page" do
    arr_app

    get new_indexer_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Assigned apps")
    expect(response.body).to include("Jackett Torznab URL or ID")
  end

  it "links to app creation when no apps exist" do
    get new_indexer_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Add an app")
    expect(response.body).to include(new_arr_app_path)
  end

  it "creates an indexer with app assignments" do
    arr_app

    expect {
      post indexers_path, params: {
        indexer: {
          name: "Second Indexer",
          jackett_id: "http://localhost:9117/api/v2.0/indexers/second-indexer/results/torznab/",
          enabled: true,
          arr_app_ids: [ arr_app.id ]
        }
      }
    }.to change(Indexer, :count).by(1)
      .and change(IndexerApp, :count).by(1)

    expect(response).to redirect_to(indexer_path(Indexer.last))
    expect(Indexer.last.jackett_id).to eq("second-indexer")
  end

  it "shows an indexer" do
    indexer

    get indexer_path(indexer)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Main Sonarr")
    expect(response.body).to include("App assignments")
    expect(response.body).to include("Sync")
  end

  it "syncs one app assignment" do
    indexer
    assignment = indexer.indexer_apps.first
    result = Sync::IndexerAppSync::Result.new(
      success?: true,
      remote_indexer_id: 42,
      message: "First Indexer synced to Main Sonarr.",
      error: nil
    )
    allow(Sync::IndexerAppSync).to receive(:call).and_return(result)

    post sync_indexer_app_path(assignment)

    expect(response).to redirect_to(indexer_path(indexer))
    expect(Sync::IndexerAppSync).to have_received(:call).with(indexer_app: assignment)
    expect(flash[:notice]).to eq("First Indexer synced to Main Sonarr.")
  end

  it "shows sync failures" do
    indexer
    assignment = indexer.indexer_apps.first
    result = Sync::IndexerAppSync::Result.new(
      success?: false,
      remote_indexer_id: nil,
      message: "Jackett URL is missing.",
      error: "Jackett URL is missing."
    )
    allow(Sync::IndexerAppSync).to receive(:call).and_return(result)

    post sync_indexer_app_path(assignment)

    expect(response).to redirect_to(indexer_path(indexer))
    expect(flash[:alert]).to eq("Jackett URL is missing.")
  end

  it "renders the edit indexer page" do
    indexer

    get edit_indexer_path(indexer)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Edit indexer")
  end

  it "updates an indexer and its assignments" do
    indexer

    patch indexer_path(indexer), params: {
      indexer: {
        name: "Updated Indexer",
        jackett_id: indexer.jackett_id,
        enabled: indexer.enabled,
        arr_app_ids: []
      }
    }

    expect(response).to redirect_to(indexer_path(indexer))
    expect(indexer.reload.name).to eq("Updated Indexer")
    expect(indexer.arr_apps).to be_empty
  end

  it "removes assignments that already have sync run history" do
    indexer
    assignment = indexer.indexer_apps.first
    sync_run = SyncRun.create!(total_count: 1)
    sync_run_item = sync_run.sync_run_items.create!(
      indexer_app: assignment,
      indexer_name: indexer.name,
      arr_app_name: arr_app.name
    )

    patch indexer_path(indexer), params: {
      indexer: {
        name: indexer.name,
        jackett_id: indexer.jackett_id,
        enabled: indexer.enabled,
        arr_app_ids: []
      }
    }

    expect(response).to redirect_to(indexer_path(indexer))
    expect(indexer.reload.arr_apps).to be_empty
    expect(sync_run_item.reload).to have_attributes(
      indexer_app_id: nil,
      indexer_name: "First Indexer",
      arr_app_name: "Main Sonarr"
    )
  end

  it "destroys an indexer" do
    indexer
    result = Sync::IndexerDestroyer::Result.new(success?: true, message: "Indexer removed.", error: nil)
    allow(Sync::IndexerDestroyer).to receive(:call).and_return(result)

    expect {
      delete indexer_path(indexer)
    }.not_to change(Indexer, :count)

    expect(response).to redirect_to(indexers_path)
    expect(Sync::IndexerDestroyer).to have_received(:call).with(indexer:)
  end

  it "does not destroy an indexer when remote cleanup fails" do
    indexer
    result = Sync::IndexerDestroyer::Result.new(
      success?: false,
      message: "Main Sonarr returned HTTP 500 while trying to remove managed indexer.",
      error: "Main Sonarr returned HTTP 500 while trying to remove managed indexer."
    )
    allow(Sync::IndexerDestroyer).to receive(:call).and_return(result)

    expect {
      delete indexer_path(indexer)
    }.not_to change(Indexer, :count)

    expect(response).to redirect_to(indexer_path(indexer))
    expect(flash[:alert]).to eq("Main Sonarr returned HTTP 500 while trying to remove managed indexer.")
  end
end
