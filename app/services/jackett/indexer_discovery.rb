module Jackett
  class IndexerDiscovery
    IndexerRecord = Data.define(:name, :jackett_id, :configured)
    Result = Data.define(:success?, :indexers, :message, :error, :http_status)

    INDEXERS_PATH = "/api/v2.0/indexers/all/results/torznab/api"

    def self.call(base_url:, api_key:, connection: nil)
      new(base_url:, api_key:, connection:).call
    end

    def initialize(base_url:, api_key:, connection: nil)
      @base_url = base_url.to_s.strip
      @api_key = api_key.to_s.strip
      @connection = connection
    end

    def call
      return failure("Add a Jackett URL before discovering indexers.") if base_url.blank?
      return failure("Add a Jackett API key before discovering indexers.") if api_key.blank?
      return failure("Jackett URL must start with http:// or https://.") unless valid_base_url?

      response = http.get(INDEXERS_PATH, t: "indexers", configured: true, apikey: api_key)
      return http_failure(response) unless response.success?

      indexers = parse_indexers(response.body)
      success(indexers, response.status)
    rescue Faraday::Error => e
      failure("Could not connect to Jackett: #{e.message}")
    rescue Nokogiri::XML::SyntaxError
      failure("Jackett responded, but Bridgarr could not read the indexer list.")
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

      def parse_indexers(body)
        document = Nokogiri::XML(body) { |config| config.strict.nonet }
        raise Nokogiri::XML::SyntaxError, "missing indexers root" unless document.at_xpath("/indexers")

        document.xpath("/indexers/indexer").filter_map do |indexer|
          jackett_id = indexer["id"]
          name = indexer.at_xpath("title")&.text
          configured = ActiveModel::Type::Boolean.new.cast(indexer["configured"])

          next unless configured
          next if jackett_id.blank? || name.blank?

          IndexerRecord.new(
            name:,
            jackett_id:,
            configured:
          )
        end
      end

      def success(indexers, http_status)
        Result.new(success?: true, indexers:, message: "Found #{indexers.size} configured Jackett indexers.", error: nil, http_status:)
      end

      def http_failure(response)
        failure("Jackett returned HTTP #{response.status}. Check the URL and API key.", http_status: response.status)
      end

      def failure(message, http_status: nil)
        Result.new(success?: false, indexers: [], message:, error: message, http_status:)
      end
  end
end
