require "json"

module Jackett
  class IndexerOperationalTest
    Result = Data.define(:success?, :item_count, :message, :error, :http_status)

    OPEN_TIMEOUT_SECONDS = 5
    READ_TIMEOUT_SECONDS = Rails.configuration.x.jackett_indexer_health_timeout_seconds
    ERROR_DETAIL_LIMIT = 500

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

      response = http.get(
        torznab_path,
        t: "search",
        cache: false,
        limit: 1,
        apikey: api_key
      )
      return http_failure(response) unless response.success?

      document = parse_response(response.body)
      return torznab_failure(document, http_status: response.status) if torznab_error(document).present?

      item_count = document.xpath("/rss/channel/item").size
      return failure("Jackett completed the live search but returned no releases.", http_status: response.status) if item_count.zero?

      success(item_count, response.status)
    rescue Faraday::TimeoutError, Net::ReadTimeout
      failure("Jackett did not complete the live search for #{jackett_id} within #{READ_TIMEOUT_SECONDS} seconds.")
    rescue Faraday::Error => e
      detail = bounded_detail(e.message)
      failure([ "Could not connect to Jackett", detail ].compact.join(": "))
    rescue Nokogiri::XML::SyntaxError
      failure("Jackett responded, but Bridgarr could not read the live-search response.", http_status: response&.status)
    end

    private

      attr_reader :base_url, :api_key, :jackett_id, :connection

      def http
        @http ||= connection || Faraday.new(url: base_url) do |faraday|
          faraday.request :url_encoded
          faraday.options.timeout = READ_TIMEOUT_SECONDS
          faraday.options.open_timeout = OPEN_TIMEOUT_SECONDS
          faraday.adapter Faraday.default_adapter
        end
      end

      def torznab_path
        "/api/v2.0/indexers/#{jackett_id}/results/torznab"
      end

      def parse_response(body)
        document = Nokogiri::XML(body) { |config| config.strict.nonet }
        return document if document.at_xpath("/rss/channel").present? || torznab_error(document).present?

        raise Nokogiri::XML::SyntaxError, "missing Torznab RSS root"
      end

      def torznab_error(document)
        document.at_xpath("/error")
      end

      def torznab_failure(document, http_status:)
        error = torznab_error(document)
        code = bounded_detail(error["code"])
        description = bounded_detail(error["description"]) || bounded_detail(error.text) || "Jackett returned an unspecified Torznab error."
        prefix = code.present? ? "Jackett live search failed with Torznab error #{code}" : "Jackett live search failed"

        failure("#{prefix}: #{description}", http_status:)
      end

      def success(item_count, http_status)
        Result.new(
          success?: true,
          item_count:,
          message: "Live search returned #{item_count} release.",
          error: nil,
          http_status:
        )
      end

      def http_failure(response)
        detail = response_error_detail(response.body)
        message = "Jackett returned HTTP #{response.status} while running the live search."
        message = "#{message} #{detail}" if detail.present?

        failure(message, http_status: response.status)
      end

      def response_error_detail(body)
        text = body.to_s.strip
        return if text.blank?

        xml_error_detail(text) || json_error_detail(text) || plain_error_detail(text)
      end

      def xml_error_detail(text)
        document = Nokogiri::XML(text) { |config| config.nonet }
        if (error = torznab_error(document))
          bounded_detail(error["description"]) || bounded_detail(error.text)
        end
      rescue Nokogiri::XML::SyntaxError
        nil
      end

      def json_error_detail(text)
        json = JSON.parse(text)
        return unless json.is_a?(Hash)

        value = json.values_at("message", "Message", "error", "Error").find { |candidate| candidate.is_a?(String) && candidate.present? }
        bounded_detail(value)
      rescue JSON::ParserError
        nil
      end

      def plain_error_detail(text)
        return if text.start_with?("<")

        bounded_detail(text)
      end

      def bounded_detail(value)
        Secrets::Redactor.call(value).to_s.squish.truncate(ERROR_DETAIL_LIMIT).presence
      end

      def failure(message, http_status: nil)
        Result.new(success?: false, item_count: 0, message:, error: message, http_status:)
      end
  end
end
