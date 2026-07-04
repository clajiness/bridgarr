module Jackett
  class ConnectionTest
    Result = Data.define(:success?, :message, :error, :http_status)

    CAPS_PATH = "/api/v2.0/indexers/all/results/torznab/api"

    def self.call(base_url:, api_key:, connection: nil)
      new(base_url:, api_key:, connection:).call
    end

    def initialize(base_url:, api_key:, connection: nil)
      @base_url = base_url.to_s.strip
      @api_key = api_key.to_s.strip
      @connection = connection
    end

    def call
      return failure("Add a Jackett URL before testing.") if base_url.blank?
      return failure("Add a Jackett API key before testing.") if api_key.blank?
      return failure("Jackett URL must start with http:// or https://.") unless valid_base_url?

      response = http.get(CAPS_PATH, t: "caps", apikey: api_key)
      return http_failure(response) unless response.success?
      return success(response.status) if torznab_caps?(response.body)

      failure("Jackett responded, but Bridgarr did not receive Torznab capabilities.", http_status: response.status)
    rescue Faraday::Error => e
      failure("Could not connect to Jackett: #{e.message}")
    rescue URI::InvalidURIError
      failure("Jackett URL is not a valid URL.")
    end

    private

      attr_reader :base_url, :api_key, :connection

      def http
        @http ||= connection || Faraday.new(url: base_url) do |faraday|
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

      def torznab_caps?(body)
        document = Nokogiri::XML(body) { |config| config.strict.nonet }
        document.at_xpath("/caps").present?
      rescue Nokogiri::XML::SyntaxError
        false
      end

      def success(http_status)
        Result.new(success?: true, message: "Jackett connection works.", error: nil, http_status:)
      end

      def http_failure(response)
        failure("Jackett returned HTTP #{response.status}. Check the URL and API key.", http_status: response.status)
      end

      def failure(message, http_status: nil)
        Result.new(success?: false, message:, error: message, http_status:)
      end
  end
end
