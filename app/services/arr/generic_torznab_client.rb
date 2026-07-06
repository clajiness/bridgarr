module Arr
  class GenericTorznabClient
    Result = Data.define(:success?, :remote_indexer_id, :message, :error, :http_status)

    INDEXER_PATH = "/api/v3/indexer"
    SCHEMA_PATH = "/api/v3/indexer/schema"

    CATEGORY_ROOTS_BY_APP_TYPE = {
      "sonarr" => [ 5000 ],
      "radarr" => [ 2000 ],
      "lidarr" => [ 3000 ],
      "whisparr" => [ 6000 ]
    }.freeze
    ANIME_CATEGORY_ROOT = 5000
    ANIME_CATEGORY_IDS = [ 5070 ].freeze
    REQUEST_TIMEOUT_SECONDS = ENV.fetch("ARR_INDEXER_SYNC_TIMEOUT_SECONDS", 150).to_i
    TIMEOUT_ADOPTION_ATTEMPTS = 4
    TIMEOUT_ADOPTION_INTERVAL_SECONDS = 0.75
    PROXY_API_KEY = "bridgarr"

    def self.call(arr_app:, name:, bridgarr_base_url:, jackett_base_url:, jackett_api_key:, jackett_id:, remote_indexer_id: nil, connection: nil, caps_client: Jackett::TorznabCaps)
      new(arr_app:, name:, bridgarr_base_url:, jackett_base_url:, jackett_api_key:, jackett_id:, remote_indexer_id:, connection:, caps_client:).call
    end

    def initialize(arr_app:, name:, bridgarr_base_url:, jackett_base_url:, jackett_api_key:, jackett_id:, remote_indexer_id: nil, connection: nil, caps_client: Jackett::TorznabCaps)
      @arr_app = arr_app
      @name = name
      @bridgarr_base_url = bridgarr_base_url.to_s.strip.delete_suffix("/")
      @jackett_base_url = jackett_base_url.to_s.strip.delete_suffix("/")
      @jackett_api_key = jackett_api_key.to_s.strip
      @jackett_id = jackett_id
      @remote_indexer_id = remote_indexer_id
      @connection = connection
      @caps_client = caps_client
    end

    def call
      return failure("Bridgarr URL is missing.") if bridgarr_base_url.blank?
      return failure("Jackett URL is missing.") if jackett_base_url.blank?
      return failure("Jackett API key is missing.") if jackett_api_key.blank?

      if (remote_indexer = find_indexer_by_id)
        return success(remote_indexer.fetch("id"), nil, "Generic Torznab indexer is already synced.")
      end

      if (managed_indexer = find_indexer_by_name)
        return success(managed_indexer.fetch("id"), nil, "Generic Torznab indexer already exists.")
      end

      compatibility_error = category_compatibility_error
      return failure(compatibility_error) if compatibility_error

      schema_response = http.get(SCHEMA_PATH)
      return http_failure(schema_response, "fetch indexer schema") unless schema_response.success?

      payload = torznab_payload(JSON.parse(schema_response.body))
      response = post_indexer(payload)
      return http_failure(response, "create Generic Torznab indexer") unless response.success?

      body = JSON.parse(response.body)
      success(body["id"], response.status)
    rescue Faraday::TimeoutError => e
      if (existing_indexer = find_existing_indexer_after_timeout)
        return success(existing_indexer.fetch("id"), nil, "Generic Torznab indexer exists after #{arr_app.name} timed out.")
      end

      failure("Could not connect to #{arr_app.name}: #{e.message}")
    rescue Faraday::Error => e
      failure("Could not connect to #{arr_app.name}: #{e.message}")
    rescue JSON::ParserError
      failure("#{arr_app.name} responded, but Bridgarr could not read the indexer response.")
    rescue KeyError
      failure("#{arr_app.name} did not return a Generic Torznab schema.")
    end

    private

      attr_reader :arr_app, :name, :bridgarr_base_url, :jackett_base_url, :jackett_api_key, :jackett_id, :remote_indexer_id, :connection, :caps_client

      def http
        @http ||= connection || Faraday.new(url: arr_app.base_url, headers: { "X-Api-Key" => arr_app.api_key }) do |faraday|
          faraday.request :url_encoded
          faraday.options.timeout = REQUEST_TIMEOUT_SECONDS
          faraday.options.open_timeout = 2
          faraday.adapter Faraday.default_adapter
        end
      end

      def torznab_payload(schemas)
        schema = schemas.find { |candidate| candidate["implementation"] == "Torznab" || candidate["configContract"] == "TorznabSettings" }
        raise KeyError unless schema

        schema.deep_dup.tap do |payload|
          payload["name"] = name
          payload["enableRss"] = true
          payload["enableAutomaticSearch"] = true
          payload["enableInteractiveSearch"] = true
          payload["fields"] = fields_with_jackett_settings(payload["fields"])
        end
      end

      def fields_with_jackett_settings(fields)
        fields.map do |field|
          field.merge("value" => field_value(field))
        end
      end

      def field_value(field)
        case field["name"]
        when "baseUrl"
          "#{bridgarr_base_url}/torznab/#{jackett_id}"
        when "apiPath"
          "/api"
        when "apiKey"
          PROXY_API_KEY
        when "categories"
          category_ids.presence || field["value"]
        when "animeCategories"
          anime_category_ids.presence || field["value"]
        else
          field["value"]
        end
      end

      def category_ids
        @category_ids ||= compatible_category_ids
      end

      def anime_category_ids
        @anime_category_ids ||= begin
          return [] unless arr_app.app_type == "sonarr"

          torznab_category_ids.select do |id|
            category_root(id) == ANIME_CATEGORY_ROOT && ANIME_CATEGORY_IDS.include?(id)
          end
        end
      end

      def torznab_category_ids
        @torznab_category_ids ||= torznab_caps_result.success? ? torznab_caps_result.category_ids : []
      end

      def torznab_caps_result
        @torznab_caps_result ||= caps_client.call(
          base_url: jackett_base_url,
          api_key: jackett_api_key,
          jackett_id:
        )
      end

      def compatible_category_ids
        @compatible_category_ids ||= begin
          return torznab_category_ids if category_roots.blank?

          torznab_category_ids.select { |id| category_roots.include?(category_root(id)) }
        end
      end

      def category_roots
        @category_roots ||= CATEGORY_ROOTS_BY_APP_TYPE.fetch(arr_app.app_type, [])
      end

      def category_compatibility_error
        return if category_roots.blank?

        unless torznab_caps_result.success?
          return "Could not inspect Torznab categories for #{name}: #{torznab_caps_result.message}"
        end

        return if compatible_category_ids.present?

        "#{name} does not expose #{arr_app.app_type.to_s.titleize}-compatible Torznab categories."
      end

      def category_root(category_id)
        category_id / 1000 * 1000
      end

      def post_indexer(payload)
        http.post(INDEXER_PATH) do |request|
          request.headers["Content-Type"] = "application/json"
          request.body = JSON.generate(payload)
        end
      end

      def remote_indexers
        response = http.get(INDEXER_PATH)
        return unless response.success?

        JSON.parse(response.body)
      end

      def find_indexer_by_id
        return if remote_indexer_id.blank?

        remote_indexers&.find { |indexer| indexer["id"] == remote_indexer_id }
      end

      def find_indexer_by_name
        remote_indexers&.find { |indexer| indexer["name"] == name }
      end

      def safe_find_existing_indexer
        find_indexer_by_name
      rescue Faraday::Error, JSON::ParserError
        nil
      end

      def find_existing_indexer_after_timeout
        TIMEOUT_ADOPTION_ATTEMPTS.times do |attempt|
          existing_indexer = safe_find_existing_indexer
          return existing_indexer if existing_indexer

          sleep TIMEOUT_ADOPTION_INTERVAL_SECONDS unless attempt == TIMEOUT_ADOPTION_ATTEMPTS - 1
        end

        nil
      end

      def success(remote_indexer_id, http_status, message = "Generic Torznab indexer created.")
        Result.new(success?: true, remote_indexer_id:, message:, error: nil, http_status:)
      end

      def http_failure(response, action)
        message = "#{arr_app.name} returned HTTP #{response.status} while trying to #{action}."
        detail = response_detail(response.body)
        message = "#{message} #{detail}" if detail.present?

        failure(message, http_status: response.status)
      end

      def failure(message, http_status: nil)
        Result.new(success?: false, remote_indexer_id: nil, message:, error: message, http_status:)
      end

      def response_detail(body)
        text = body.to_s.strip
        return if text.blank?

        parsed = JSON.parse(text)
        validation_messages(parsed).presence
      rescue JSON::ParserError
        text.truncate(300)
      end

      def validation_messages(parsed)
        messages =
          case parsed
          when Array
            parsed.filter_map { |item| validation_message(item) }
          when Hash
            hash_messages(parsed)
          else
            []
          end

        messages.first(3).join(" ")
      end

      def hash_messages(parsed)
        if parsed["errors"].is_a?(Hash)
          parsed["errors"].flat_map { |field, errors| Array(errors).map { |error| "#{field}: #{error}" } }
        else
          [ parsed["message"], parsed["error"] ].compact
        end
      end

      def validation_message(item)
        return unless item.is_a?(Hash)

        message = item["errorMessage"] || item["message"] || item["error"]
        return if message.blank?

        property_name = item["propertyName"]
        property_name.present? ? "#{property_name}: #{message}" : message
      end
  end
end
