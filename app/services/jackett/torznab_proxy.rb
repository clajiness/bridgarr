require "cgi"

module Jackett
  class TorznabProxy
    Result = Data.define(:body, :http_status, :content_type)

    TORZNAB_CONTENT_TYPE = "application/rss+xml"
    OPEN_TIMEOUT_SECONDS = 5
    READ_TIMEOUT_SECONDS = ENV.fetch("JACKETT_TORZNAB_TIMEOUT_SECONDS", 120).to_i

    def self.call(base_url:, bridgarr_base_url:, api_key:, jackett_id:, query_params:, connection: nil)
      new(base_url:, bridgarr_base_url:, api_key:, jackett_id:, query_params:, connection:).call
    end

    def initialize(base_url:, bridgarr_base_url:, api_key:, jackett_id:, query_params:, connection: nil)
      @base_url = base_url.to_s.strip.delete_suffix("/")
      @bridgarr_base_url = bridgarr_base_url.to_s.strip.delete_suffix("/")
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
      content_type = jackett_response.headers["content-type"].presence || TORZNAB_CONTENT_TYPE
      response(
        rewrite_download_links(jackett_response.body, content_type),
        jackett_response.status,
        content_type
      )
    rescue Faraday::TimeoutError, Net::ReadTimeout
      response(timeout_message, :bad_gateway, "text/plain")
    rescue Faraday::Error => e
      response("Could not connect to Jackett: #{e.message}", :bad_gateway, "text/plain")
    end

    private

      attr_reader :base_url, :bridgarr_base_url, :api_key, :jackett_id, :query_params, :connection

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

      def forwarded_params
        query_params.merge("apikey" => api_key)
      end

      def timeout_message
        request_type = query_params["t"].presence || "Torznab request"
        "Jackett did not return #{request_type} results for #{jackett_id} within #{READ_TIMEOUT_SECONDS} seconds."
      end

      def rewrite_download_links(body, content_type)
        return body if bridgarr_base_url.blank?
        return body unless xml_response?(body, content_type)

        document = Nokogiri::XML(body)
        return body if document.root.blank?

        changed = false

        document.xpath("//item/link").each do |link|
          rewritten_url = rewritten_download_url(link.text)
          next if rewritten_url == link.text

          link.content = rewritten_url
          changed = true
        end

        document.xpath("//item/enclosure[@url]").each do |enclosure|
          rewritten_url = rewritten_download_url(enclosure["url"])
          next if rewritten_url == enclosure["url"]

          enclosure["url"] = rewritten_url
          changed = true
        end

        changed ? document.to_xml : body
      rescue Nokogiri::XML::SyntaxError, URI::InvalidURIError
        body
      end

      def xml_response?(body, content_type)
        content_type.to_s.include?("xml") || body.to_s.lstrip.start_with?("<")
      end

      def rewritten_download_url(url)
        uri = URI.parse(url.to_s)
        return url unless jackett_download_url?(uri)

        query_params = Rack::Utils.parse_nested_query(uri.query).except("jackett_apikey", "apikey")
        query = query_params.to_query
        bridgarr_url = "#{bridgarr_base_url}/torznab/#{CGI.escape(jackett_id)}/download"
        query.present? ? "#{bridgarr_url}?#{query}" : bridgarr_url
      end

      def jackett_download_url?(uri)
        jackett_uri = URI.parse(base_url)
        uri.scheme == jackett_uri.scheme &&
          uri.host == jackett_uri.host &&
          uri.port == jackett_uri.port &&
          uri.path.start_with?("/dl/#{jackett_id}/")
      end

      def response(body, http_status, content_type)
        Result.new(body:, http_status:, content_type:)
      end
  end
end
