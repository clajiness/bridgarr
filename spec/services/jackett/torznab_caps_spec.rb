require "rails_helper"

RSpec.describe Jackett::TorznabCaps do
  CapsResponse = Struct.new(:status, :body, keyword_init: true) do
    def success?
      status.between?(200, 299)
    end
  end

  class FakeCapsConnection
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

  it "fetches Torznab category IDs from Jackett caps" do
    connection = FakeCapsConnection.new(
      CapsResponse.new(
        status: 200,
        body: <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <caps>
            <categories>
              <category id="5000" name="TV">
                <subcat id="5030" name="TV/SD" />
                <subcat id="5040" name="TV/HD" />
              </category>
              <category id="2000" name="Movies" />
            </categories>
          </caps>
        XML
      )
    )

    result = described_class.call(
      base_url: "http://localhost:9117/",
      api_key: "jackett-api-key",
      jackett_id: "eztv",
      connection:
    )

    expect(result).to be_success
    expect(result.category_ids).to eq([ 2000, 5000, 5030, 5040 ])
    expect(connection.path).to eq("/api/v2.0/indexers/eztv/results/torznab")
    expect(connection.params).to eq(t: "caps", apikey: "jackett-api-key")
  end

  it "fails when Jackett returns invalid caps XML" do
    connection = FakeCapsConnection.new(CapsResponse.new(status: 200, body: "<html></html>"))

    result = described_class.call(
      base_url: "http://localhost:9117",
      api_key: "jackett-api-key",
      jackett_id: "eztv",
      connection:
    )

    expect(result).not_to be_success
    expect(result.message).to eq("Jackett responded, but Bridgarr could not read the Torznab caps.")
  end

  it "fails when Jackett returns an unsuccessful response" do
    connection = FakeCapsConnection.new(CapsResponse.new(status: 401, body: "Unauthorized"))

    result = described_class.call(
      base_url: "http://localhost:9117",
      api_key: "bad-key",
      jackett_id: "eztv",
      connection:
    )

    expect(result).not_to be_success
    expect(result.message).to eq("Jackett returned HTTP 401 while fetching Torznab caps.")
  end
end
