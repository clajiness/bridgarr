module Arr
  class TorznabCategoryPolicy
    CATEGORY_ROOTS_BY_APP_TYPE = {
      "sonarr" => [ 5000 ],
      "radarr" => [ 2000 ],
      "lidarr" => [ 3000 ],
      "whisparr" => [ 6000 ]
    }.freeze
    CATEGORY_MODES = %w[ auto custom none ].freeze
    ANIME_CATEGORY_IDS = [ 5070 ].freeze

    def initialize(
      app_type:,
      category_ids: nil,
      jackett_category_ids: nil,
      arr_default_category_ids: nil,
      arr_default_anime_category_ids: nil,
      category_mode: "auto",
      custom_category_ids: nil
    )
      @app_type = app_type.to_s
      @jackett_category_ids = normalize_category_ids(jackett_category_ids.nil? ? category_ids : jackett_category_ids)
      @arr_default_category_ids = normalize_category_ids(arr_default_category_ids)
      @arr_default_anime_category_ids = normalize_category_ids(arr_default_anime_category_ids)
      @category_mode = CATEGORY_MODES.include?(category_mode.to_s) ? category_mode.to_s : "auto"
      @custom_category_ids = normalize_category_ids(custom_category_ids)
    end

    def category_ids
      return custom_category_ids if custom?
      return [] if none?

      return default_category_ids if default_category_ids.present?
      return [] if default_anime_category_ids.present?

      root_fallback_category_ids
    end

    def anime_category_ids
      return custom_anime_category_ids if custom?
      return [] if none?

      default_anime_category_ids
    end

    def compatible?
      return true if custom? || none?

      category_ids.present? || anime_category_ids.present?
    end

    def app_filtered?
      category_roots.present?
    end

    def root_fallback?
      default_category_ids.blank? && default_anime_category_ids.blank? && root_fallback_category_ids.present?
    end

    def custom?
      category_mode == "custom"
    end

    def none?
      category_mode == "none"
    end

    def manual?
      custom? || none?
    end

    private

      attr_reader :app_type,
        :jackett_category_ids,
        :arr_default_category_ids,
        :arr_default_anime_category_ids,
        :category_mode,
        :custom_category_ids

      def default_category_ids
        @default_category_ids ||= ordered_intersection(arr_default_category_ids, jackett_category_ids)
      end

      def default_anime_category_ids
        @default_anime_category_ids ||= ordered_intersection(arr_default_anime_category_ids, jackett_category_ids)
      end

      def root_fallback_category_ids
        @root_fallback_category_ids ||= ordered_intersection(category_roots, jackett_category_ids)
      end

      def custom_anime_category_ids
        @custom_anime_category_ids ||= custom_category_ids.select { |id| ANIME_CATEGORY_IDS.include?(id) }
      end

      def category_roots
        @category_roots ||= CATEGORY_ROOTS_BY_APP_TYPE.fetch(app_type, [])
      end

      def ordered_intersection(left, right)
        left.select { |id| right.include?(id) }
      end

      def normalize_category_ids(value)
        Array(value).flat_map { |category_id| category_id.to_s.scan(/\d+/) }.map(&:to_i).select(&:positive?).uniq
      end
  end
end
