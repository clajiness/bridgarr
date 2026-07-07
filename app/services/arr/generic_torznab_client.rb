module Arr
  class GenericTorznabClient
    Result = Data.define(:success?, :skipped?, :remote_indexer_id, :message, :error, :http_status)

    INDEXER_PATH = "/api/v3/indexer"
    SCHEMA_PATH = "/api/v3/indexer/schema"

    REQUEST_TIMEOUT_SECONDS = ENV.fetch("ARR_INDEXER_SYNC_TIMEOUT_SECONDS", 150).to_i
    TIMEOUT_ADOPTION_ATTEMPTS = 4
    TIMEOUT_ADOPTION_INTERVAL_SECONDS = 0.75
    PROXY_API_KEY = "bridgarr"

    def self.call(**attributes)
      new(**attributes).call
    end

    def initialize(
      arr_app:,
      name:,
      bridgarr_base_url:,
      jackett_base_url:,
      jackett_api_key:,
      jackett_id:,
      remote_indexer_id: nil,
      connection_mode: "direct",
      category_mode: "auto",
      custom_category_ids: nil,
      connection: nil,
      caps_client: Jackett::TorznabCaps
    )
      @arr_app = arr_app
      @name = name
      @bridgarr_base_url = bridgarr_base_url.to_s.strip.delete_suffix("/")
      @jackett_base_url = jackett_base_url.to_s.strip.delete_suffix("/")
      @jackett_api_key = jackett_api_key.to_s.strip
      @jackett_id = jackett_id
      @remote_indexer_id = remote_indexer_id
      @connection_mode = connection_mode.to_s.presence || "direct"
      @category_mode = category_mode.presence || "auto"
      @custom_category_ids = normalize_category_ids(custom_category_ids)
      @connection = connection
      @caps_client = caps_client
    end

    def call
      return failure("Bridgarr URL is missing.") if connection_mode_bridged? && bridgarr_base_url.blank?
      return failure("Jackett URL is missing.") if jackett_base_url.blank?
      return failure("Jackett API key is missing.") if jackett_api_key.blank?

      if (remote_indexer = find_indexer_by_id)
        return sync_existing_indexer(remote_indexer, already_synced_message)
      end

      if (managed_indexer = find_indexer_by_name)
        return sync_existing_indexer(managed_indexer, already_exists_message)
      end

      schema_failure = load_torznab_schema
      return schema_failure if schema_failure

      compatibility_error = category_compatibility_error
      return skipped(compatibility_error) if compatibility_error

      log_category_selection

      payload = torznab_payload
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

      attr_reader :arr_app,
        :name,
        :bridgarr_base_url,
        :jackett_base_url,
        :jackett_api_key,
        :jackett_id,
        :remote_indexer_id,
        :connection_mode,
        :category_mode,
        :custom_category_ids,
        :connection,
        :caps_client

      def http
        @http ||= connection || Faraday.new(url: arr_app.base_url, headers: { "X-Api-Key" => arr_app.api_key }) do |faraday|
          faraday.request :url_encoded
          faraday.options.timeout = REQUEST_TIMEOUT_SECONDS
          faraday.options.open_timeout = 2
          faraday.adapter Faraday.default_adapter
        end
      end

      def load_torznab_schema
        return if @torznab_schema

        response = http.get(SCHEMA_PATH)
        return http_failure(response, "fetch indexer schema") unless response.success?

        @torznab_schema = select_torznab_schema(JSON.parse(response.body))
        raise KeyError unless @torznab_schema

        nil
      end

      def select_torznab_schema(schemas)
        schemas.find { |candidate| candidate["implementation"] == "Torznab" || candidate["configContract"] == "TorznabSettings" }
      end

      def torznab_payload
        torznab_schema.deep_dup.tap do |payload|
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
          torznab_base_url
        when "apiPath"
          "/api"
        when "apiKey"
          torznab_api_key
        when "categories"
          category_field_value(field)
        when "animeCategories"
          anime_category_field_value(field)
        else
          field["value"]
        end
      end

      def category_field_value(_field)
        category_ids
      end

      def anime_category_field_value(_field)
        anime_category_ids
      end

      def category_ids
        category_policy.category_ids
      end

      def anime_category_ids
        category_policy.anime_category_ids
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

      def category_policy
        @category_policy ||= Arr::TorznabCategoryPolicy.new(
          app_type: arr_app.app_type,
          jackett_category_ids: category_policy_manual? ? [] : torznab_category_ids,
          arr_default_category_ids:,
          arr_default_anime_category_ids:,
          category_mode:,
          custom_category_ids:
        )
      end

      def category_compatibility_error
        return if category_policy.manual?

        unless torznab_caps_result.success?
          return "Could not inspect Torznab categories for #{name}: #{torznab_caps_result.message}"
        end

        return if category_policy.compatible?

        "No compatible default categories were found for #{name}. #{arr_app.name}'s Generic Torznab defaults do not overlap with the categories advertised by this Jackett indexer. Review the category mode or choose custom categories."
      end

      def category_policy_manual?
        %w[ custom none ].include?(category_mode)
      end

      def torznab_base_url
        if connection_mode_bridged?
          "#{bridgarr_base_url}/torznab/#{jackett_id}"
        else
          "#{jackett_base_url}/api/v2.0/indexers/#{jackett_id}/results/torznab"
        end
      end

      def torznab_api_key
        connection_mode_bridged? ? PROXY_API_KEY : jackett_api_key
      end

      def connection_mode_bridged?
        connection_mode == "bridged"
      end

      def sync_existing_indexer(remote_indexer, message)
        return success(remote_indexer.fetch("id"), nil, message) unless remote_indexer_configurable?(remote_indexer)

        schema_failure = load_torznab_schema
        return schema_failure if schema_failure

        compatibility_error = category_compatibility_error
        return skipped(compatibility_error) if compatibility_error

        log_category_selection
        return success(remote_indexer.fetch("id"), nil, message) if remote_indexer_matches?(remote_indexer)

        response = update_indexer(remote_indexer)
        return http_failure(response, "update Generic Torznab indexer") unless response.success?

        body = parse_response_body(response.body)
        success(body["id"] || remote_indexer.fetch("id"), response.status, "Generic Torznab indexer updated.")
      end

      def remote_indexer_configurable?(remote_indexer)
        remote_indexer["fields"].is_a?(Array)
      end

      def remote_indexer_matches?(remote_indexer)
        fields = remote_indexer.fetch("fields").index_by { |field| field.fetch("name") }

        fields.dig("baseUrl", "value") == torznab_base_url &&
          fields.dig("apiPath", "value") == "/api" &&
          fields.dig("apiKey", "value") == torznab_api_key &&
          category_matches?(fields["categories"]) &&
          category_matches?(fields["animeCategories"], anime: true)
      end

      def category_matches?(field, anime: false)
        return true unless field

        expected = anime ? anime_category_field_value(field) : category_field_value(field)
        category_values(field["value"]) == category_values(expected)
      end

      def category_values(value)
        normalize_category_ids(value).sort
      end

      def updated_indexer_payload(remote_indexer)
        remote_indexer.deep_dup.tap do |payload|
          payload["name"] = name
          payload["enableRss"] = true
          payload["enableAutomaticSearch"] = true
          payload["enableInteractiveSearch"] = true
          payload["fields"] = fields_with_jackett_settings(payload["fields"])
        end
      end

      def update_indexer(remote_indexer)
        http.put("#{INDEXER_PATH}/#{remote_indexer.fetch("id")}") do |request|
          request.headers["Content-Type"] = "application/json"
          request.body = JSON.generate(updated_indexer_payload(remote_indexer))
        end
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

      def torznab_schema
        @torznab_schema || raise(KeyError)
      end

      def arr_default_category_ids
        @arr_default_category_ids ||= schema_category_ids("categories")
      end

      def arr_default_anime_category_ids
        @arr_default_anime_category_ids ||= schema_category_ids("animeCategories")
      end

      def schema_category_ids(field_name)
        field = torznab_schema.fetch("fields", []).find { |candidate| candidate["name"] == field_name }

        normalize_category_ids(field&.fetch("value", nil))
      end

      def normalize_category_ids(value)
        Array(value).flat_map { |category_id| category_id.to_s.scan(/\d+/) }.map(&:to_i).select(&:positive?).uniq
      end

      def log_category_selection
        return if category_policy_manual?

        Rails.logger.info(
          {
            message: "Selected Torznab categories",
            arr_app: arr_app.name,
            app_type: arr_app.app_type,
            indexer: name,
            jackett_id:,
            connection_mode:,
            category_mode:,
            arr_default_categories: arr_default_category_ids,
            arr_default_anime_categories: arr_default_anime_category_ids,
            selected_categories: category_ids,
            selected_anime_categories: anime_category_ids,
            root_fallback: category_policy.root_fallback?
          }.to_json
        )
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
        Result.new(success?: true, skipped?: false, remote_indexer_id:, message:, error: nil, http_status:)
      end

      def already_synced_message
        "Generic Torznab indexer is already synced."
      end

      def already_exists_message
        "Generic Torznab indexer already exists."
      end

      def skipped(message)
        Result.new(success?: false, skipped?: true, remote_indexer_id: nil, message:, error: message, http_status: nil)
      end

      def http_failure(response, action)
        message = "#{arr_app.name} returned HTTP #{response.status} while trying to #{action}."
        detail = response_detail(response.body)
        message = "#{message} #{detail}" if detail.present?

        failure(message, http_status: response.status)
      end

      def failure(message, http_status: nil)
        Result.new(success?: false, skipped?: false, remote_indexer_id: nil, message:, error: message, http_status:)
      end

      def response_detail(body)
        text = body.to_s.strip
        return if text.blank?

        parsed = JSON.parse(text)
        validation_messages(parsed).presence
      rescue JSON::ParserError
        text.truncate(300)
      end

      def parse_response_body(body)
        text = body.to_s.strip
        return {} if text.blank?

        JSON.parse(text)
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
