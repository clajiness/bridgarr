require "rails_helper"

RSpec.describe Diagnostics::AssignmentReport do
  it "builds a useful report without exposing secrets" do
    arr_app = ArrApp.create!(
      name: "Main Sonarr",
      app_type: "sonarr",
      base_url: "http://user:password@localhost:8989/?apikey=url-secret",
      api_key: "arr-secret"
    )
    indexer = Indexer.create!(name: "EZTV", jackett_id: "eztv")
    assignment = IndexerApp.create!(
      arr_app:,
      indexer:,
      last_status: "error",
      last_error: "GET http://localhost/api?apikey=jackett-secret returned HTTP 401"
    )

    report = described_class.call(indexer_app: assignment)

    expect(report).to include("Bridgarr assignment diagnostic report")
    expect(report).to include("Failure kind: authentication")
    expect(report).to include("Recommended action:")
    expect(report).to include("Application URL: http://localhost:8989")
    expect(report).not_to include("password", "url-secret", "jackett-secret", "arr-secret")
  end
end
