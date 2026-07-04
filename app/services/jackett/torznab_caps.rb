module Jackett
  class TorznabCaps
    Result = Data.define(:success?, :category_ids, :message, :error, :http_status)

    def self.call(base_url:, api_key:, jackett_id:, connection: nil)
      new(base_url:, api_key:, jackett_id:, connection:).call
    end

    def initialize(base_url:, api_key:, jackett_id:, connection: nil)
      @base_url = base_url.to_s.strip.delete_suffix("/")
      @api_key = api_key.to_s.strip
      @jackett_id = jackett_id.to_s.strip
      @connection = connection
    end

    def call
      return failure("Jackett URL is missing.") if base_url.blank?
      return failure("Jackett API key is missing.") if api_key.blank?
      return failure("Jackett indexer ID is missing.") if jackett_id.blank?

      response = http.get(torznab_path, t: "caps", apikey: api_key)
      return http_failure(response) unless response.success?

      category_ids = parse_category_ids(response.body)
      success(category_ids, response.status)
    rescue Faraday::Error => e
      failure("Could not connect to Jackett: #{e.message}")
    rescue Nokogiri::XML::SyntaxError
      failure("Jackett responded, but Bridgarr could not read the Torznab caps.")
    end

    private

      attr_reader :base_url, :api_key, :jackett_id, :connection

      def http
        @http ||= connection || Faraday.new(url: base_url) do |faraday|
          faraday.request :url_encoded
          faraday.options.timeout = 5
          faraday.options.open_timeout = 2
          faraday.adapter Faraday.default_adapter
        end
      end

      def torznab_path
        "/api/v2.0/indexers/#{jackett_id}/results/torznab"
      end

      def parse_category_ids(body)
        document = Nokogiri::XML(body) { |config| config.strict.nonet }
        raise Nokogiri::XML::SyntaxError, "missing caps root" unless document.at_xpath("/caps")

        document.xpath("/caps/categories//*[self::category or self::subcat]").filter_map do |category|
          category["id"].presence&.to_i
        end.uniq.sort
      end

      def success(category_ids, http_status)
        Result.new(
          success?: true,
          category_ids:,
          message: "Found #{category_ids.size} Torznab categories.",
          error: nil,
          http_status:
        )
      end

      def http_failure(response)
        failure("Jackett returned HTTP #{response.status} while fetching Torznab caps.", http_status: response.status)
      end

      def failure(message, http_status: nil)
        Result.new(success?: false, category_ids: [], message:, error: message, http_status:)
      end
  end
end
