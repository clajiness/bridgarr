module Arr
  class ConnectionTest
    Result = Data.define(:success?, :message, :error, :http_status, :app_name, :version)

    STATUS_PATH = "/api/v3/system/status"

    def self.call(base_url:, api_key:, connection: nil)
      new(base_url:, api_key:, connection:).call
    end

    def initialize(base_url:, api_key:, connection: nil)
      @base_url = base_url.to_s.strip
      @api_key = api_key.to_s.strip
      @connection = connection
    end

    def call
      return failure("Add an app base URL before testing.") if base_url.blank?
      return failure("Add an app API key before testing.") if api_key.blank?
      return failure("App base URL must start with http:// or https://.") unless valid_base_url?

      response = http.get(STATUS_PATH)
      return http_failure(response) unless response.success?

      body = JSON.parse(response.body)
      success(response.status, app_name: body["appName"], version: body["version"])
    rescue Faraday::Error => e
      failure("Could not connect to app: #{e.message}")
    rescue JSON::ParserError
      failure("The app responded, but Bridgarr could not read its status response.", http_status: response&.status)
    end

    private

      attr_reader :base_url, :api_key, :connection

      def http
        @http ||= connection || Faraday.new(url: base_url, headers: { "X-Api-Key" => api_key }) do |faraday|
          faraday.request :url_encoded
          faraday.options.timeout = 5
          faraday.options.open_timeout = 2
          faraday.adapter Faraday.default_adapter
        end
      end

      def valid_base_url?
        uri = URI.parse(base_url)
        uri.is_a?(URI::HTTP) && uri.host.present?
      rescue URI::InvalidURIError
        false
      end

      def success(http_status, app_name:, version:)
        app_label = app_name.presence || "App"
        Result.new(success?: true, message: "#{app_label} connection works.", error: nil, http_status:, app_name:, version:)
      end

      def http_failure(response)
        failure("App returned HTTP #{response.status}. Check the URL and API key.", http_status: response.status)
      end

      def failure(message, http_status: nil)
        Result.new(success?: false, message:, error: message, http_status:, app_name: nil, version: nil)
      end
  end
end
