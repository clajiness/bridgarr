require "digest"

module Jackett
  class CategoryCatalog
    REFRESH_AFTER = 15.minutes

    Result = Data.define(:categories, :refreshed_at, :state, :message) do
      def available?
        categories.any?
      end

      def current?
        state == "current"
      end

      def stale?
        state == "stale"
      end
    end

    def self.call(indexer:, caps_client: TorznabCaps, now: Time.current)
      new(indexer:, caps_client:, now:).call
    end

    def self.cached(indexer:)
      new(indexer:, caps_client: TorznabCaps, now: Time.current).cached_result
    end

    def initialize(indexer:, caps_client:, now:)
      @indexer = indexer
      @caps_client = caps_client
      @now = now
    end

    def call
      if jackett_base_url.blank? || jackett_api_key.blank?
        return fallback_result(
          "Jackett is not configured. Showing the last category list that loaded successfully.",
          unavailable_message: "Connect Jackett in Settings to load this indexer's categories.",
          unavailable_state: "unconfigured"
        )
      end
      return cached_result if cache_current?

      caps_result = caps_client.call(
        base_url: jackett_base_url,
        api_key: jackett_api_key,
        jackett_id: indexer.jackett_id
      )
      return fallback_result("Jackett could not be refreshed. Showing the last category list that loaded successfully.") unless caps_result.success?

      categories = indexer.record_jackett_categories!(caps_result.categories, source: catalog_source, refreshed_at: now)
      Result.new(
        categories:,
        refreshed_at: now,
        state: "current",
        message: ("Jackett did not advertise any categories for this indexer." if categories.empty?)
      )
    end

    def cached_result
      return unavailable_result unless cached?

      Result.new(
        categories: indexer.jackett_categories,
        refreshed_at: indexer.jackett_category_catalog_refreshed_at,
        state: "current",
        message: nil
      )
    end

    private

      attr_reader :indexer, :caps_client, :now

      def fallback_result(message, unavailable_message: nil, unavailable_state: "unavailable")
        return unavailable_result(unavailable_message, state: unavailable_state) unless cached?

        Result.new(
          categories: indexer.jackett_categories,
          refreshed_at: indexer.jackett_category_catalog_refreshed_at,
          state: "stale",
          message:
        )
      end

      def unavailable_result(message = nil, state: "unavailable")
        message ||= "Categories are not available from Jackett right now. Reload this page to try again."
        Result.new(categories: [], refreshed_at: nil, state:, message:)
      end

      def cached?
        indexer.jackett_category_catalog_refreshed_at.present? &&
          indexer.jackett_category_catalog.is_a?(Array) &&
          indexer.jackett_category_catalog_source == catalog_source
      end

      def cache_current?
        cached? && indexer.jackett_category_catalog_refreshed_at >= REFRESH_AFTER.ago(now)
      end

      def catalog_source
        @catalog_source ||= Digest::SHA256.hexdigest(
          [ jackett_base_url.delete_suffix("/"), Setting.jackett_api_key_version, indexer.jackett_id ].join("\0")
        )
      end

      def jackett_base_url
        @jackett_base_url ||= Setting.fetch_value(Setting::JACKETT_BASE_URL_KEY).to_s.strip
      end

      def jackett_api_key
        @jackett_api_key ||= Setting.fetch_value(Setting::JACKETT_API_KEY_KEY).to_s.strip
      end
  end
end
