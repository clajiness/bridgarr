class SyncRun < ApplicationRecord
  STATUSES = %w[queued running succeeded failed partial].freeze
  MODES = %w[bulk].freeze

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
    %w[succeeded failed partial].include?(status)
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
    unfinished = items.where(status: %w[queued running]).exists?

    attributes = {
      total_count: total,
      success_count: successes,
      failure_count: failures
    }

    if unfinished
      attributes[:status] = started_at.present? ? "running" : "queued"
    else
      attributes[:status] = final_status(successes:, failures:)
      attributes[:finished_at] = Time.current
    end

    update!(attributes)
  end

  private

    def final_status(successes:, failures:)
      return "succeeded" if failures.zero?
      return "failed" if successes.zero?

      "partial"
    end
end
