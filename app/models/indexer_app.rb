class IndexerApp < ApplicationRecord
  CONNECTION_MODES = %w[ direct bridged ].freeze
  CATEGORY_MODES = %w[ auto custom none ].freeze
  SEARCH_MODE_SETTING_KEYS = %w[enable_rss enable_automatic_search enable_interactive_search].freeze
  DESIRED_SETTING_KEYS = [ *SEARCH_MODE_SETTING_KEYS, "connection_mode", "category_mode", "custom_categories" ].freeze
  PLAN_STATES = %w[create update unchanged not_applicable conflict orphaned unreachable invalid].freeze

  belongs_to :indexer
  belongs_to :arr_app
  has_many :sync_run_items, dependent: :nullify

  before_validation :normalize_settings
  before_update :mark_changed_desired_state
  after_commit :broadcast_live_refreshes

  validates :indexer_id, uniqueness: { scope: :arr_app_id }
  validates :connection_mode, inclusion: { in: CONNECTION_MODES }
  validates :category_mode, inclusion: { in: CATEGORY_MODES }
  validates :last_plan_state, inclusion: { in: PLAN_STATES }, allow_nil: true
  validate :custom_categories_are_category_id_list
  validate :custom_categories_are_present_for_custom_mode
  validate :desired_state_does_not_change_during_active_sync, on: :update

  scope :with_enabled_parents, -> do
    joins(:indexer, :arr_app).where(indexers: { enabled: true }, arr_apps: { enabled: true })
  end
  scope :enabled_assignments, -> do
    where(enable_rss: true).or(where(enable_automatic_search: true)).or(where(enable_interactive_search: true))
  end
  scope :disabled_assignments, -> do
    where(enable_rss: false, enable_automatic_search: false, enable_interactive_search: false)
  end

  def record_sync_result(result, synced_at: Time.current)
    attributes = {
      remote_indexer_id: result.remote_indexer_id || remote_indexer_id,
      last_synced_at: synced_at,
      last_status: sync_status_for(result),
      last_error: Secrets::Redactor.call(result.error)
    }
    if result.success?
      attributes[:last_applied_at] = synced_at
      attributes[:last_applied_settings] = desired_settings_snapshot
      attributes[:last_plan_state] = "unchanged"
      if result.respond_to?(:desired_digest) && result.desired_digest.present?
        attributes[:last_applied_digest] = result.desired_digest
        attributes[:last_desired_digest] = result.desired_digest
        attributes[:last_remote_digest] = result.desired_digest
      end
      if connection_mode_bridged?
        attributes[:proxy_api_key_version] = Setting.proxy_api_key_version
      else
        attributes[:jackett_api_key_version] = Setting.jackett_api_key_version
      end
    end

    update!(attributes)
  end

  def custom_category_ids
    custom_categories.to_s.scan(/\d+/).map(&:to_i).select(&:positive?).uniq
  end

  def desired_settings_snapshot
    {
      "enable_rss" => enable_rss?,
      "enable_automatic_search" => enable_automatic_search?,
      "enable_interactive_search" => enable_interactive_search?,
      "connection_mode" => connection_mode,
      "category_mode" => category_mode,
      "custom_categories" => custom_categories
    }
  end

  def last_applied_settings_snapshot
    snapshot = last_applied_settings
    return unless snapshot.is_a?(Hash)

    normalized = normalize_legacy_snapshot(snapshot.stringify_keys).slice(*DESIRED_SETTING_KEYS)
    return unless normalized.keys.sort == DESIRED_SETTING_KEYS.sort
    return unless SEARCH_MODE_SETTING_KEYS.all? { |key| normalized[key].in?([ true, false ]) }
    return unless normalized["connection_mode"].in?(CONNECTION_MODES)
    return unless normalized["category_mode"].in?(CATEGORY_MODES)
    return unless valid_snapshot_categories?(normalized)

    normalized
  end

  def custom_categories?
    custom_category_ids.any?
  end

  def custom_settings?
    !all_search_modes_enabled? || !connection_mode_direct? || !category_mode_auto?
  end

  def any_search_mode_enabled?
    enable_rss? || enable_automatic_search? || enable_interactive_search?
  end

  def all_search_modes_enabled?
    enable_rss? && enable_automatic_search? && enable_interactive_search?
  end

  def search_modes_disabled?
    !any_search_mode_enabled?
  end

  def active_sync_run_item
    sync_run_items.active.order(created_at: :desc).first
  end

  def active_sync?
    active_sync_run_item.present?
  end

  def reconciliation_attention?
    last_plan_state.in?(%w[conflict orphaned unreachable invalid])
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

  def api_key_update_required?
    if connection_mode_bridged?
      proxy_api_key_version != Setting.proxy_api_key_version
    else
      jackett_api_key_version != Setting.jackett_api_key_version
    end
  end

  private

    def broadcast_live_refreshes
      %w[assignment_matrix dashboard readiness indexers arr_apps].each do |stream|
        broadcast_refresh_later_to stream
      end
    end

    def normalize_settings
      self.connection_mode = connection_mode.presence || "direct"
      self.category_mode = category_mode.presence || "auto"
      self.proxy_api_key_version = nil if connection_mode_direct?
      self.jackett_api_key_version = nil if connection_mode_bridged?

      raw_categories = custom_categories.to_s.strip
      if raw_categories.blank?
        self.custom_categories = nil
      elsif valid_category_list_text?(raw_categories)
        self.custom_categories = raw_categories.scan(/\d+/).map(&:to_i).uniq.join(",")
      end
    end

    def mark_changed_desired_state
      return unless desired_state_changing?

      self.last_plan_state = remote_indexer_id.present? ? "update" : "create"
      self.last_inspected_at = nil
      self.last_desired_digest = nil
    end

    def desired_state_does_not_change_during_active_sync
      return unless desired_state_changing? && sync_run_items.active.exists?

      errors.add(:base, "Wait for the active assignment sync to finish before changing its settings.")
    end

    def desired_state_changing?
      will_save_change_to_enable_rss? ||
        will_save_change_to_enable_automatic_search? ||
        will_save_change_to_enable_interactive_search? ||
        will_save_change_to_connection_mode? ||
        will_save_change_to_category_mode? ||
        will_save_change_to_custom_categories?
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

    def valid_snapshot_categories?(snapshot)
      categories = snapshot["custom_categories"]
      return snapshot["category_mode"] != "custom" if categories.blank?

      valid_category_list_text?(categories.to_s)
    end

    def normalize_legacy_snapshot(snapshot)
      return snapshot unless snapshot.key?("enabled")
      return snapshot if SEARCH_MODE_SETTING_KEYS.any? { |key| snapshot.key?(key) }

      legacy_enabled = snapshot["enabled"]
      return snapshot unless legacy_enabled.in?([ true, false ])

      snapshot.merge(SEARCH_MODE_SETTING_KEYS.index_with { legacy_enabled })
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
