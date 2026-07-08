class SyncRunItem < ApplicationRecord
  ACTIVE_STATUSES = %w[queued running retrying].freeze
  TERMINAL_STATUSES = %w[succeeded failed skipped].freeze
  STATUSES = (ACTIVE_STATUSES + TERMINAL_STATUSES).freeze

  belongs_to :sync_run
  belongs_to :indexer_app, optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :attempt_count, numericality: { greater_than_or_equal_to: 0 }
  validates :max_attempts, numericality: { greater_than: 0 }

  scope :ordered, -> { order(:indexer_name, :arr_app_name, :id) }
  scope :active, -> { where(status: ACTIVE_STATUSES) }

  after_update_commit -> { broadcast_replace_later_to sync_run }

  def indexer
    indexer_app&.indexer
  end

  def arr_app
    indexer_app&.arr_app
  end

  def indexer_label
    indexer&.name || indexer_name || "Removed indexer"
  end

  def arr_app_label
    arr_app&.name || arr_app_name || "Removed app"
  end

  def queued?
    status == "queued"
  end

  def running?
    status == "running"
  end

  def retrying?
    status == "retrying"
  end

  def active?
    ACTIVE_STATUSES.include?(status)
  end

  def terminal?
    TERMINAL_STATUSES.include?(status)
  end

  def succeeded?
    status == "succeeded"
  end

  def failed?
    status == "failed"
  end

  def skipped?
    status == "skipped"
  end

  def mark_running!
    now = Time.current

    update!(
      status: "running",
      started_at: started_at || now,
      last_attempt_at: now,
      next_retry_at: nil,
      attempt_count: attempt_count + 1,
      finished_at: nil,
      error: nil,
      error_kind: nil,
      retryable: false
    )
  end

  def record_result!(result, finished_at: Time.current)
    sanitized_error = result.success? ? nil : Secrets::Redactor.call(result.error)
    classification = sanitized_error.present? ? Sync::ErrorClassifier.call(sanitized_error, skipped: result.skipped?) : nil

    update!(
      status: sync_status_for(result),
      finished_at:,
      error: sanitized_error,
      error_kind: classification&.kind,
      retryable: classification&.retryable? || false,
      next_retry_at: nil
    )
  end

  def record_retry!(error:, classification:, next_retry_at:)
    update!(
      status: "retrying",
      finished_at: nil,
      error: Secrets::Redactor.call(error),
      error_kind: classification.kind,
      retryable: true,
      next_retry_at:
    )
  end

  def to_partial_path
    "sync_runs/sync_run_item"
  end

  private

    def sync_status_for(result)
      return "succeeded" if result.success?
      return "skipped" if result.skipped?

      "failed"
    end
end
