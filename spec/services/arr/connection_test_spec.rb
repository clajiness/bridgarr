require "rails_helper"

RSpec.describe Arr::ConnectionTest do
  ArrResponse = Struct.new(:status, :body, keyword_init: true) do
    def success?
      status.between?(200, 299)
    end
  end

  class FakeArrConnection
    attr_reader :path

    def initialize(response)
      @response = response
    end

    def get(path)
      @path = path
      @response
    end
  end

  it "checks the app system status endpoint" do
    connection = FakeArrConnection.new(
      ArrResponse.new(status: 200, body: { appName: "Sonarr", version: "4.0.0" }.to_json)
    )

    result = described_class.call(
      base_url: "http://localhost:8989",
      api_key: "sonarr-api-key",
      connection:
    )

    expect(result).to be_success
    expect(result.message).to eq("Sonarr connection works.")
    expect(result.app_name).to eq("Sonarr")
    expect(result.version).to eq("4.0.0")
    expect(connection.path).to eq("/api/v3/system/status")
  end

  it "fails when the app returns an unsuccessful response" do
    connection = FakeArrConnection.new(ArrResponse.new(status: 401, body: "Unauthorized"))

    result = described_class.call(
      base_url: "http://localhost:8989",
      api_key: "bad-key",
      connection:
    )

    expect(result).not_to be_success
    expect(result.message).to eq("App returned HTTP 401. Check the URL and API key.")
  end

  it "fails when the app does not return JSON" do
    connection = FakeArrConnection.new(ArrResponse.new(status: 200, body: "<html></html>"))

    result = described_class.call(
      base_url: "http://localhost:8989",
      api_key: "sonarr-api-key",
      connection:
    )

    expect(result).not_to be_success
    expect(result.message).to eq("The app responded, but Bridgarr could not read its status response.")
    expect(result.http_status).to eq(200)
  end

  it "requires an app base URL" do
    result = described_class.call(base_url: "", api_key: "sonarr-api-key")

    expect(result).not_to be_success
    expect(result.message).to eq("Add an app base URL before testing.")
  end

  it "requires an app API key" do
    result = described_class.call(base_url: "http://localhost:8989", api_key: "")

    expect(result).not_to be_success
    expect(result.message).to eq("Add an app API key before testing.")
  end

  it "requires an HTTP URL" do
    result = described_class.call(base_url: "localhost:8989", api_key: "sonarr-api-key")

    expect(result).not_to be_success
    expect(result.message).to eq("App base URL must start with http:// or https://.")
  end
end
