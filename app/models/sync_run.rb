class SyncRun < ApplicationRecord
  STATUSES = %w[queued running succeeded failed partial skipped mismatched].freeze
  MODES = %w[bulk assignment].freeze

  has_many :sync_run_items, dependent: :destroy

  validates :status, inclusion: { in: STATUSES }
  validates :mode, inclusion: { in: MODES }

  scope :recent, -> { order(created_at: :desc) }

  after_update_commit -> { broadcast_replace_later_to self }

  def queued?
    status == "queued"
  end

  def running?
    status == "running"
  end

  def complete?
    %w[succeeded failed partial skipped mismatched].include?(status)
  end

  def mark_running!
    return if running? || complete?

    update!(status: "running", started_at: Time.current)
  end

  def refresh_status!
    items = sync_run_items.reload
    total = items.count
    successes = items.where(status: "succeeded").count
    failures = items.where(status: "failed").count
    skipped = items.where(status: "skipped").count
    mismatches = items.where(status: "mismatched").count
    unfinished = items.active.exists?

    attributes = {
      total_count: total,
      success_count: successes,
      failure_count: failures,
      skipped_count: skipped,
      mismatch_count: mismatches
    }

    if unfinished
      attributes[:status] = started_at.present? ? "running" : "queued"
    else
      attributes[:status] = final_status(successes:, failures:, skipped:, mismatches:)
      attributes[:finished_at] = Time.current
    end

    update!(attributes)
  end

  def abandon!(message: "Sync run was abandoned.")
    return if complete?

    sanitized_message = Secrets::Redactor.call(message)

    transaction do
      sync_run_items.active.find_each do |item|
        classification = Sync::ErrorClassifier.call(sanitized_message)
        item.update!(
          status: "failed",
          finished_at: Time.current,
          error: sanitized_message,
          error_kind: classification.kind,
          retryable: classification.retryable?,
          next_retry_at: nil
        )
      end

      update!(
        status: "failed",
        failure_count: sync_run_items.where(status: "failed").count,
        success_count: sync_run_items.where(status: "succeeded").count,
        skipped_count: sync_run_items.where(status: "skipped").count,
        mismatch_count: sync_run_items.where(status: "mismatched").count,
        total_count: sync_run_items.count,
        finished_at: Time.current,
        error: sanitized_message
      )
    end
  end

  private

    def final_status(successes:, failures:, skipped:, mismatches:)
      return "succeeded" if failures.zero? && skipped.zero? && mismatches.zero?
      return "mismatched" if failures.zero? && mismatches.positive?
      return "skipped" if successes.zero? && failures.zero? && skipped.positive?
      return "failed" if successes.zero?

      "partial"
    end
end
