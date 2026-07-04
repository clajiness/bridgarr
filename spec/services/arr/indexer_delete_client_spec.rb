require "rails_helper"

RSpec.describe Arr::IndexerDeleteClient do
  ArrDeleteResponse = Struct.new(:status, keyword_init: true) do
    def success?
      status.between?(200, 299)
    end
  end

  class FakeArrDeleteConnection
    attr_reader :delete_path

    def initialize(response)
      @response = response
    end

    def delete(path)
      @delete_path = path
      @response
    end
  end

  let(:arr_app) do
    ArrApp.new(
      name: "Main Sonarr",
      app_type: "sonarr",
      base_url: "http://localhost:8989",
      api_key: "sonarr-api-key"
    )
  end

  it "removes a remote indexer by ID" do
    connection = FakeArrDeleteConnection.new(ArrDeleteResponse.new(status: 200))

    result = described_class.call(arr_app:, remote_indexer_id: 42, connection:)

    expect(result).to be_success
    expect(result.message).to eq("Managed indexer removed from Main Sonarr.")
    expect(connection.delete_path).to eq("/api/v3/indexer/42")
  end

  it "fails when the Arr app rejects the delete request" do
    connection = FakeArrDeleteConnection.new(ArrDeleteResponse.new(status: 404))

    result = described_class.call(arr_app:, remote_indexer_id: 42, connection:)

    expect(result).not_to be_success
    expect(result.message).to eq("Main Sonarr returned HTTP 404 while trying to remove managed indexer.")
  end
end
