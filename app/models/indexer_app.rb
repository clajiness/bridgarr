class IndexerApp < ApplicationRecord
  CONNECTION_MODES = %w[ direct bridged ].freeze
  CATEGORY_MODES = %w[ auto custom none ].freeze

  belongs_to :indexer
  belongs_to :arr_app
  has_many :sync_run_items, dependent: :nullify

  before_validation :normalize_settings

  validates :indexer_id, uniqueness: { scope: :arr_app_id }
  validates :connection_mode, inclusion: { in: CONNECTION_MODES }
  validates :category_mode, inclusion: { in: CATEGORY_MODES }
  validate :custom_categories_are_category_id_list
  validate :custom_categories_are_present_for_custom_mode

  def record_sync_result(result, synced_at: Time.current)
    update!(
      remote_indexer_id: result.remote_indexer_id || remote_indexer_id,
      last_synced_at: synced_at,
      last_status: sync_status_for(result),
      last_error: Secrets::Redactor.call(result.error)
    )
  end

  def custom_category_ids
    custom_categories.to_s.scan(/\d+/).map(&:to_i).select(&:positive?).uniq
  end

  def custom_categories?
    custom_category_ids.any?
  end

  def active_sync_run_item
    sync_run_items.active.order(created_at: :desc).first
  end

  def active_sync?
    active_sync_run_item.present?
  end

  def connection_mode_direct?
    connection_mode == "direct"
  end

  def connection_mode_bridged?
    connection_mode == "bridged"
  end

  def category_mode_auto?
    category_mode == "auto"
  end

  def category_mode_custom?
    category_mode == "custom"
  end

  def category_mode_none?
    category_mode == "none"
  end

  private

    def normalize_settings
      self.connection_mode = connection_mode.presence || "direct"
      self.category_mode = category_mode.presence || "auto"

      raw_categories = custom_categories.to_s.strip
      if raw_categories.blank?
        self.custom_categories = nil
      elsif valid_category_list_text?(raw_categories)
        self.custom_categories = raw_categories.scan(/\d+/).map(&:to_i).uniq.join(",")
      end
    end

    def custom_categories_are_category_id_list
      return if custom_categories.blank?
      return if valid_category_list_text?(custom_categories)

      errors.add(:custom_categories, "must be a comma-separated list of positive category IDs")
    end

    def custom_categories_are_present_for_custom_mode
      return unless category_mode_custom?
      return if custom_category_ids.any?

      errors.add(:custom_categories, "must be present when category mode is custom")
    end

    def valid_category_list_text?(value)
      ids = value.scan(/\d+/)

      value.match?(/\A[\d,\s]+\z/) && ids.any? && ids.all? { |id| id.to_i.positive? }
    end

    def sync_status_for(result)
      return "ok" if result.success?
      return "skipped" if result.skipped?
      return "mismatch" if Sync::ErrorClassifier.call(result.error).kind == "category_mismatch"

      "error"
    end
end
