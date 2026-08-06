module Arr
  class IndexerInventory
    Result = Data.define(:success?, :indexers, :torznab_schema, :message, :error, :http_status)

    INDEXER_PATH = "/api/v3/indexer"
    SCHEMA_PATH = "/api/v3/indexer/schema"
    REQUEST_TIMEOUT_SECONDS = ENV.fetch("ARR_INDEXER_INSPECTION_TIMEOUT_SECONDS", "15").to_i

    def self.call(arr_app:, connection: nil)
      new(arr_app:, connection:).call
    end

    def initialize(arr_app:, connection:)
      @arr_app = arr_app
      @connection = connection
    end

    def call
      indexers_response = http.get(INDEXER_PATH)
      return http_failure(indexers_response, "inspect indexers") unless indexers_response.success?

      schema_response = http.get(SCHEMA_PATH)
      return http_failure(schema_response, "inspect the Generic Torznab schema") unless schema_response.success?

      indexers = JSON.parse(indexers_response.body)
      schemas = JSON.parse(schema_response.body)
      unless valid_indexers?(indexers) && schemas.is_a?(Array) && schemas.all?(Hash)
        return failure("#{arr_app.name} responded, but its indexer inventory had an unexpected shape.")
      end

      torznab_schema = schemas.find { |candidate| candidate["implementation"] == "Torznab" || candidate["configContract"] == "TorznabSettings" }
      return failure("#{arr_app.name} did not return a Generic Torznab schema.") unless torznab_schema

      Result.new(
        success?: true,
        indexers:,
        torznab_schema:,
        message: "Inspected #{arr_app.name}.",
        error: nil,
        http_status: schema_response.status
      )
    rescue Faraday::Error => e
      failure("Could not inspect #{arr_app.name}: #{e.message}")
    rescue JSON::ParserError
      failure("#{arr_app.name} responded, but Bridgarr could not read its indexer inventory.")
    end

    private

      attr_reader :arr_app, :connection

      def valid_indexers?(indexers)
        indexers.is_a?(Array) && indexers.all? do |indexer|
          next false unless indexer.is_a?(Hash)

          id = Integer(indexer["id"].to_s, 10, exception: false)
          id&.positive?
        end
      end

      def http
        @http ||= connection || Faraday.new(url: arr_app.base_url, headers: { "X-Api-Key" => arr_app.api_key }) do |faraday|
          faraday.options.timeout = REQUEST_TIMEOUT_SECONDS
          faraday.options.open_timeout = 2
          faraday.adapter Faraday.default_adapter
        end
      end

      def http_failure(response, action)
        failure(
          "#{arr_app.name} returned HTTP #{response.status} while Bridgarr tried to #{action}.",
          http_status: response.status
        )
      end

      def failure(message, http_status: nil)
        message = Secrets::Redactor.call(message)
        Result.new(
          success?: false,
          indexers: [],
          torznab_schema: nil,
          message:,
          error: message,
          http_status:
        )
      end
  end
end
