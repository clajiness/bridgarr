class SyncRun < ApplicationRecord
  STATUSES = %w[queued running succeeded failed partial skipped mismatched].freeze
  MODES = %w[bulk assignment].freeze

  has_many :sync_run_items, dependent: :destroy

  validates :status, inclusion: { in: STATUSES }
  validates :mode, inclusion: { in: MODES }

  scope :recent, -> { order(created_at: :desc) }

  after_update_commit -> { broadcast_replace_later_to self, attributes: { method: :morph } }
  after_commit :broadcast_live_refreshes

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
    with_lock do
      return false if running? || complete?

      update!(status: "running", started_at: Time.current)
    end

    true
  end

  def refresh_status!
    with_lock do
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
        attributes[:status] = final_status(successes:, failures:, mismatches:)
        attributes[:finished_at] = Time.current
      end

      update!(attributes)
    end
  end

  def abandon!(message: "Sync run was abandoned.")
    sanitized_message = Secrets::Redactor.call(message)
    classification = Sync::ErrorClassifier.call(sanitized_message)
    abandoned_item = false

    transaction do
      sync_run_items.active.lock.find_each do |item|
        next unless item.active?

        item.update!(
          status: "failed",
          finished_at: Time.current,
          error: sanitized_message,
          error_kind: classification.kind,
          retryable: classification.retryable?,
          next_retry_at: nil
        )
        abandoned_item = true
      end

      if abandoned_item
        reload
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
      elsif !sync_run_items.exists?
        reload
        return if complete?

        update!(
          status: "failed",
          total_count: 0,
          success_count: 0,
          failure_count: 0,
          skipped_count: 0,
          mismatch_count: 0,
          finished_at: Time.current,
          error: sanitized_message
        )
      else
        refresh_status!
      end
    end
  end

  private

    def broadcast_live_refreshes
      broadcast_refresh_later_to "dashboard"
      broadcast_refresh_later_to "sync_runs"
    end

    def final_status(successes:, failures:, mismatches:)
      return "succeeded" if failures.zero? && mismatches.zero?
      return "mismatched" if failures.zero? && mismatches.positive?
      return "failed" if successes.zero?

      "partial"
    end
end
