require "rails_helper"

RSpec.describe Jackett::ConnectionTest do
  Response = Struct.new(:status, :body, keyword_init: true) do
    def success?
      status.between?(200, 299)
    end
  end

  class FakeConnection
    attr_reader :path, :params

    def initialize(response)
      @response = response
    end

    def get(path, params)
      @path = path
      @params = params
      @response
    end
  end

  it "connects to the Jackett Torznab caps endpoint" do
    connection = FakeConnection.new(Response.new(status: 200, body: "<caps></caps>"))

    result = described_class.call(
      base_url: "http://localhost:9117",
      api_key: "jackett-api-key",
      connection:
    )

    expect(result).to be_success
    expect(result.message).to eq("Jackett connection works.")
    expect(connection.path).to eq("/api/v2.0/indexers/all/results/torznab/api")
    expect(connection.params).to eq(t: "caps", apikey: "jackett-api-key")
  end

  it "fails when Jackett returns an unsuccessful response" do
    connection = FakeConnection.new(Response.new(status: 401, body: "Unauthorized"))

    result = described_class.call(
      base_url: "http://localhost:9117",
      api_key: "bad-key",
      connection:
    )

    expect(result).not_to be_success
    expect(result.message).to eq("Jackett returned HTTP 401. Check the URL and API key.")
  end

  it "fails when Jackett does not return Torznab caps XML" do
    connection = FakeConnection.new(Response.new(status: 200, body: "<html></html>"))

    result = described_class.call(
      base_url: "http://localhost:9117",
      api_key: "jackett-api-key",
      connection:
    )

    expect(result).not_to be_success
    expect(result.message).to eq("Jackett responded, but Bridgarr did not receive Torznab capabilities.")
  end

  it "requires a Jackett URL" do
    result = described_class.call(base_url: "", api_key: "jackett-api-key")

    expect(result).not_to be_success
    expect(result.message).to eq("Add a Jackett URL before testing.")
  end

  it "requires a Jackett API key" do
    result = described_class.call(base_url: "http://localhost:9117", api_key: "")

    expect(result).not_to be_success
    expect(result.message).to eq("Add a Jackett API key before testing.")
  end

  it "requires an HTTP URL" do
    result = described_class.call(base_url: "localhost:9117", api_key: "jackett-api-key")

    expect(result).not_to be_success
    expect(result.message).to eq("Jackett URL must start with http:// or https://.")
  end
end
