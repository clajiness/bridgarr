module Arr
  class IndexerDeleteClient
    Result = Data.define(:success?, :message, :error, :http_status)

    def self.call(arr_app:, remote_indexer_id:, connection: nil)
      new(arr_app:, remote_indexer_id:, connection:).call
    end

    def initialize(arr_app:, remote_indexer_id:, connection: nil)
      @arr_app = arr_app
      @remote_indexer_id = remote_indexer_id
      @routes = ApiRoutes.for(app_type: arr_app.app_type)
      @connection = connection
    end

    def call
      return failure("Remote indexer ID is missing.") if remote_indexer_id.blank?

      response = http.delete(routes.indexer(remote_indexer_id))
      return success(response.status) if response.success?

      failure("#{arr_app.name} returned HTTP #{response.status} while trying to remove managed indexer.", http_status: response.status)
    rescue Faraday::Error => e
      failure("Could not connect to #{arr_app.name}: #{e.message}")
    end

    private

      attr_reader :arr_app, :remote_indexer_id, :routes, :connection

      def http
        @http ||= connection || Faraday.new(url: arr_app.base_url, headers: { "X-Api-Key" => arr_app.api_key }) do |faraday|
          faraday.request :url_encoded
          faraday.options.timeout = 5
          faraday.options.open_timeout = 2
          faraday.adapter Faraday.default_adapter
        end
      end

      def success(http_status)
        Result.new(success?: true, message: "Managed indexer removed from #{arr_app.name}.", error: nil, http_status:)
      end

      def failure(message, http_status: nil)
        Result.new(success?: false, message:, error: message, http_status:)
      end
  end
end
