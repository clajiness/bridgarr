module Jackett
  class DownloadProxy
    Result = Data.define(:body, :http_status, :content_type)

    TORRENT_CONTENT_TYPE = "application/x-bittorrent"

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

      jackett_response = http.get(download_path, forwarded_params)
      response(
        jackett_response.body,
        jackett_response.status,
        jackett_response.headers["content-type"].presence || TORRENT_CONTENT_TYPE
      )
    rescue Faraday::Error => e
      response("Could not connect to Jackett: #{e.message}", :bad_gateway, "text/plain")
    end

    private

      attr_reader :base_url, :api_key, :jackett_id, :query_params, :connection

      def http
        @http ||= connection || Faraday.new(url: base_url) do |faraday|
          faraday.request :url_encoded
          faraday.options.timeout = 30
          faraday.options.open_timeout = 2
          faraday.adapter Faraday.default_adapter
        end
      end

      def download_path
        "/dl/#{jackett_id}/"
      end

      def forwarded_params
        query_params.except("apikey", "jackett_apikey").merge("jackett_apikey" => api_key)
      end

      def response(body, http_status, content_type)
        Result.new(body:, http_status:, content_type:)
      end
  end
end
