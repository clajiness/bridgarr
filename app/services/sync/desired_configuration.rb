require "digest"

module Sync
  class DesiredConfiguration
    Result = Data.define(:success?, :configuration, :message, :error)

    class Configuration
      attr_reader :attributes

      def initialize(attributes)
        @attributes = attributes.deep_stringify_keys.freeze
      end

      def digest
        DesiredConfiguration.digest(attributes)
      end

      def redacted_attributes
        attributes.merge("apiKey" => "[REDACTED]")
      end
    end

    def self.call(indexer_app:, torznab_schema:, caps_client: Jackett::TorznabCaps, caps_cache: {})
      new(indexer_app:, torznab_schema:, caps_client:, caps_cache:).call
    end

    def self.digest(attributes)
      Digest::SHA256.hexdigest(JSON.generate(canonicalize(attributes)))
    end

    def self.canonicalize(value)
      case value
      when Hash
        value.deep_stringify_keys.sort.to_h.transform_values { |nested| canonicalize(nested) }
      when Array
        value.map { |nested| canonicalize(nested) }
      else
        value
      end
    end

    def initialize(indexer_app:, torznab_schema:, caps_client:, caps_cache:)
      @indexer_app = indexer_app
      @torznab_schema = torznab_schema
      @caps_client = caps_client
      @caps_cache = caps_cache
    end

    def call
      return failure("Enable #{indexer.name} before reconciling this assignment.") unless indexer.enabled?
      return failure("Enable #{arr_app.name} before reconciling this assignment.") unless arr_app.enabled?
      return failure("Jackett URL is missing.") if jackett_base_url.blank?
      return failure("Jackett API key is missing.") if jackett_api_key.blank?
      return failure("Bridgarr URL is missing for a bridged assignment.") if indexer_app.connection_mode_bridged? && bridgarr_base_url.blank?
      return failure("Bridgarr proxy API key is missing for a bridged assignment.") if indexer_app.connection_mode_bridged? && proxy_api_key.blank?
      return failure("#{arr_app.name} did not return a Generic Torznab schema.") if torznab_schema.blank?
      return failure("#{arr_app.name} did not return configurable Generic Torznab fields.") unless configurable_schema?

      compatibility_error = category_compatibility_error
      return failure(compatibility_error) if compatibility_error

      configuration = Configuration.new(
        "name" => remote_name,
        "enableRss" => indexer_app.enabled?,
        "enableAutomaticSearch" => indexer_app.enabled?,
        "enableInteractiveSearch" => indexer_app.enabled?,
        "baseUrl" => torznab_base_url,
        "apiPath" => "/api",
        "apiKey" => torznab_api_key,
        "categories" => category_policy.category_ids.sort,
        "animeCategories" => category_policy.anime_category_ids.sort
      )

      Result.new(success?: true, configuration:, message: "Desired configuration calculated.", error: nil)
    end

    private

      REMOTE_NAME_SUFFIX = " (Bridgarr)"

      attr_reader :indexer_app, :torznab_schema, :caps_client, :caps_cache

      delegate :indexer, :arr_app, to: :indexer_app

      def remote_name
        indexer.name.end_with?(REMOTE_NAME_SUFFIX) ? indexer.name : "#{indexer.name}#{REMOTE_NAME_SUFFIX}"
      end

      def jackett_base_url
        @jackett_base_url ||= Setting.fetch_value(Setting::JACKETT_BASE_URL_KEY).to_s.strip.delete_suffix("/")
      end

      def jackett_api_key
        @jackett_api_key ||= Setting.fetch_value(Setting::JACKETT_API_KEY_KEY).to_s.strip
      end

      def bridgarr_base_url
        @bridgarr_base_url ||= Setting.fetch_value(Setting::BRIDGARR_BASE_URL_KEY).to_s.strip.delete_suffix("/")
      end

      def proxy_api_key
        @proxy_api_key ||= Setting.proxy_api_key.to_s.strip
      end

      def torznab_base_url
        if indexer_app.connection_mode_bridged?
          "#{bridgarr_base_url}/torznab/#{indexer.jackett_id}"
        else
          "#{jackett_base_url}/api/v2.0/indexers/#{indexer.jackett_id}/results/torznab"
        end
      end

      def torznab_api_key
        indexer_app.connection_mode_bridged? ? proxy_api_key : jackett_api_key
      end

      def category_policy
        @category_policy ||= Arr::TorznabCategoryPolicy.new(
          app_type: arr_app.app_type,
          jackett_category_ids: manual_categories? ? [] : torznab_caps_result.category_ids,
          arr_default_category_ids: schema_category_ids("categories"),
          arr_default_anime_category_ids: schema_category_ids("animeCategories"),
          category_mode: indexer_app.category_mode,
          custom_category_ids: indexer_app.custom_category_ids
        )
      end

      def category_compatibility_error
        return if manual_categories?
        return "Could not inspect Torznab categories for #{indexer.name}: #{torznab_caps_result.message}" unless torznab_caps_result.success?
        return if category_policy.compatible?

        "No compatible default categories were found for #{indexer.name} in #{arr_app.name}. Review the assignment's category mode."
      end

      def manual_categories?
        indexer_app.category_mode_custom? || indexer_app.category_mode_none?
      end

      def torznab_caps_result
        caps_cache[caps_cache_key] ||= caps_client.call(
          base_url: jackett_base_url,
          api_key: jackett_api_key,
          jackett_id: indexer.jackett_id
        )
      end

      def caps_cache_key
        [ jackett_base_url, indexer.jackett_id ]
      end

      def schema_category_ids(field_name)
        field = torznab_schema.fetch("fields", []).find { |candidate| candidate["name"] == field_name }
        Array(field&.fetch("value", nil)).flat_map { |value| value.to_s.scan(/\d+/) }.map(&:to_i).select(&:positive?).uniq
      end

      def configurable_schema?
        fields = torznab_schema["fields"]
        return false unless fields.is_a?(Array)

        field_names = fields.filter_map { |field| field["name"] if field.is_a?(Hash) }
        %w[baseUrl apiPath apiKey].all? { |field_name| field_names.include?(field_name) }
      end

      def failure(message)
        message = Secrets::Redactor.call(message)
        Result.new(success?: false, configuration: nil, message:, error: message)
      end
  end
end
