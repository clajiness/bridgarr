require "json"

module ProxyActivity
  class Recorder
    SENSITIVE_PARAMS = %w[apikey jackett_apikey].freeze
    ERROR_BODY_LIMIT = 500

    def self.call(indexer:, jackett_id:, request_type:, query_params:, result:, duration_ms:)
      new(indexer:, jackett_id:, request_type:, query_params:, result:, duration_ms:).call
    end

    def initialize(indexer:, jackett_id:, request_type:, query_params:, result:, duration_ms:)
      @indexer = indexer
      @jackett_id = jackett_id.to_s
      @request_type = request_type.presence || "search"
      @query_params = query_params.to_h
      @result = result
      @duration_ms = duration_ms.to_i
    end

    def call
      ProxyRequest.create!(
        indexer:,
        jackett_id:,
        request_type:,
        query: sanitized_params["q"].presence,
        categories: sanitized_params["cat"].presence,
        http_status: result.http_status,
        duration_ms:,
        item_count: item_count,
        error: error_message,
        query_params: sanitized_params.to_json
      )
    rescue StandardError => e
      Rails.logger.warn("Could not record proxy request: #{e.class}: #{e.message}")
      nil
    end

    private

      attr_reader :indexer, :jackett_id, :request_type, :query_params, :result, :duration_ms

      def sanitized_params
        @sanitized_params ||= query_params.except(*SENSITIVE_PARAMS).sort.to_h
      end

      def item_count
        return nil if request_type == "download"
        return nil unless xml_response?

        Nokogiri::XML(result.body).xpath("//item").size
      rescue Nokogiri::XML::SyntaxError
        nil
      end

      def error_message
        return nil if result.http_status.to_i.between?(200, 399)

        result.body.to_s.truncate(ERROR_BODY_LIMIT)
      end

      def xml_response?
        result.content_type.to_s.include?("xml") || result.body.to_s.lstrip.start_with?("<")
      end
  end
end
