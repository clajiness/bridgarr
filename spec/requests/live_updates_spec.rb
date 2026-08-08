require "rails_helper"

RSpec.describe "Live page updates", type: :request do
  let!(:arr_app) do
    ArrApp.create!(name: "Sonarr", app_type: "sonarr", base_url: "http://sonarr:8989", api_key: "key")
  end
  let!(:indexer) { Indexer.create!(name: "1337x", jackett_id: "1337x") }
  let!(:assignment) { IndexerApp.create!(arr_app:, indexer:) }
  let!(:sync_run) { SyncRun.create! }

  it "subscribes dashboard and readiness pages to their scoped updates" do
    get root_path

    expect(subscribed_streams).to include("dashboard")
    expect(refresh_preferences).to eq(method: "morph", scroll: "preserve")
    expect(document.at_css("body")["data-controller"].split).to include("refresh-safety")

    get readiness_path

    expect(subscribed_streams).to include("readiness")
    expect(subscribed_streams).not_to include("dashboard")
  end

  it "subscribes health and catalog pages to their scoped updates" do
    {
      health_path => "health",
      indexers_path => "indexers",
      arr_apps_path => "arr_apps",
      sync_runs_path => "sync_runs"
    }.each do |path, stream|
      get path

      expect(subscribed_streams).to include(stream)
    end
  end

  it "subscribes detail pages to their record updates" do
    get indexer_path(indexer)
    expect(subscribed_streams).to include("indexers")

    get arr_app_path(arr_app)
    expect(subscribed_streams).to include("arr_apps")

    get sync_run_path(sync_run)
    expect(subscribed_streams).to include(sync_run.to_gid_param)
  end

  it "keeps the assignment matrix subscription" do
    get indexer_apps_path

    expect(subscribed_streams).to include("assignment_matrix")
  end

  private

    def document
      Nokogiri::HTML(response.body)
    end

    def subscribed_streams
      document.css("turbo-cable-stream-source").filter_map do |source|
        Turbo::StreamsChannel.verified_stream_name(source["signed-stream-name"])
      end
    end

    def refresh_preferences
      {
        method: document.at_css('meta[name="turbo-refresh-method"]')["content"],
        scroll: document.at_css('meta[name="turbo-refresh-scroll"]')["content"]
      }
    end
end
