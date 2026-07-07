module Arr
  class TorznabCategoryPolicy
    CATEGORY_ROOTS_BY_APP_TYPE = {
      "sonarr" => [ 5000 ],
      "radarr" => [ 2000 ],
      "lidarr" => [ 3000 ],
      "whisparr" => [ 6000 ]
    }.freeze
    CATEGORY_MODES = %w[ auto custom none ].freeze
    ANIME_CATEGORY_ROOT = 5000
    ANIME_CATEGORY_IDS = [ 5070 ].freeze

    def initialize(app_type:, category_ids:, category_mode: "auto", custom_category_ids: nil)
      @app_type = app_type.to_s
      @available_category_ids = Array(category_ids).map(&:to_i).uniq
      @category_mode = CATEGORY_MODES.include?(category_mode.to_s) ? category_mode.to_s : "auto"
      @custom_category_ids = Array(custom_category_ids).map(&:to_i).select(&:positive?).uniq
    end

    def category_ids
      return custom_category_ids if custom?
      return [] if none?
      return available_category_ids if category_roots.blank?

      base_category_ids
    end

    def anime_category_ids
      return [] unless app_type == "sonarr"

      category_ids.select do |id|
        category_root(id) == ANIME_CATEGORY_ROOT && ANIME_CATEGORY_IDS.include?(id)
      end
    end

    def compatible?
      return true if custom? || none?

      category_roots.blank? || base_category_ids.present?
    end

    def app_filtered?
      category_roots.present?
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

      attr_reader :app_type, :available_category_ids, :category_mode, :custom_category_ids

      def base_category_ids
        @base_category_ids ||= available_category_ids.select do |id|
          category_roots.include?(category_root(id))
        end
      end

      def category_roots
        @category_roots ||= CATEGORY_ROOTS_BY_APP_TYPE.fetch(app_type, [])
      end

      def category_root(category_id)
        category_id / 1000 * 1000
      end
  end
end
