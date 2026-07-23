require "rails_helper"

RSpec.describe "Proxy activity", type: :request do
  it "shows all matching proxy failures with error details" do
    indexer = Indexer.create!(name: "ExtraTorrent.st", jackett_id: "extratorrent-st")
    other_indexer = Indexer.create!(name: "1337x", jackett_id: "1337x")

    7.times do |index|
      ProxyRequest.create!(
        indexer:,
        jackett_id: indexer.jackett_id,
        request_type: "tvsearch",
        query: "Silo #{index}",
        categories: "5000,5030",
        http_status: 400,
        item_count: 0,
        duration_ms: 55_000 + index,
        error: "FlareSolverr timeout #{index}",
        created_at: index.minutes.ago
      )
    end
    ProxyRequest.create!(
      indexer: other_indexer,
      jackett_id: other_indexer.jackett_id,
      request_type: "search",
      query: "Movie",
      http_status: 200,
      item_count: 3,
      duration_ms: 100
    )

    get proxy_activity_path(status: "failed")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Proxy activity")
    expect(response.body).to include("7 requests match the selected filters")
    expect(response.body).to include("FlareSolverr timeout 0")
    expect(response.body).to include("FlareSolverr timeout 6")
    expect(response.body).not_to include("Movie")

    get proxy_activity_path(status: "failed", indexer_id: other_indexer.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("No proxy requests match those filters.")
  end

  it "paginates requests while preserving filters" do
    indexer = Indexer.create!(name: "Paginated Indexer", jackett_id: "paginated-indexer")
    12.times do |index|
      ProxyRequest.create!(
        indexer:,
        jackett_id: indexer.jackett_id,
        request_type: "search",
        query: "Request-#{index.to_s.rjust(2, "0")}",
        http_status: 500,
        duration_ms: 100,
        created_at: Time.current + index.seconds
      )
    end

    get proxy_activity_path(status: "failed", page: 2, per_page: 10)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Showing 11–12 of 12 requests", "Request-00", "Request-01")
    expect(response.body).not_to include("Request-11")
    expect(response.body).to include("status=failed")
  end
end
