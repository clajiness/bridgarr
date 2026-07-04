module Jackett
  class TorznabProxy
    Result = Data.define(:body, :http_status, :content_type)

    TORZNAB_CONTENT_TYPE = "application/rss+xml"

    def self.call(base_url:, api_key:, jackett_id:, query_params:, connection: nil)
      new(base_url:, api_key:, jackett_id:, query_params:, connection:).call
    end

    def initialize(base_url:, api_key:, jackett_id:, query_params:, connection: nil)
      @base_url = base_url.to_s.strip.delete_suffix("/")
      @api_key = api_key.to_s.strip
      @jackett_id = jackett_id.to_s.strip
      @query_params = query_params.to_h
      @connection = connection
    end

    def call
      return response("Jackett URL is missing.", :bad_gateway, "text/plain") if base_url.blank?
      return response("Jackett API key is missing.", :bad_gateway, "text/plain") if api_key.blank?
      return response("Jackett indexer ID is missing.", :bad_request, "text/plain") if jackett_id.blank?

      jackett_response = http.get(torznab_path, forwarded_params)
      response(
        jackett_response.body,
        jackett_response.status,
        jackett_response.headers["content-type"].presence || TORZNAB_CONTENT_TYPE
      )
    rescue Faraday::Error => e
      response("Could not connect to Jackett: #{e.message}", :bad_gateway, "text/plain")
    end

    private

      attr_reader :base_url, :api_key, :jackett_id, :query_params, :connection

      def http
        @http ||= connection || Faraday.new(url: base_url) do |faraday|
          faraday.request :url_encoded
          faraday.options.timeout = 15
          faraday.options.open_timeout = 2
          faraday.adapter Faraday.default_adapter
        end
      end

      def torznab_path
        "/api/v2.0/indexers/#{jackett_id}/results/torznab"
      end

      def forwarded_params
        query_params.merge("apikey" => api_key)
      end

      def response(body, http_status, content_type)
        Result.new(body:, http_status:, content_type:)
      end
  end
end
