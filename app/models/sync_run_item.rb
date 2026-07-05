class SyncRunItem < ApplicationRecord
  STATUSES = %w[queued running succeeded failed skipped].freeze

  belongs_to :sync_run
  belongs_to :indexer_app

  validates :status, inclusion: { in: STATUSES }

  scope :ordered, -> { joins(indexer_app: %i[indexer arr_app]).order("indexers.name", "arr_apps.name") }

  after_update_commit -> { broadcast_replace_later_to sync_run }

  delegate :indexer, :arr_app, to: :indexer_app

  def queued?
    status == "queued"
  end

  def running?
    status == "running"
  end

  def succeeded?
    status == "succeeded"
  end

  def failed?
    status == "failed"
  end

  def mark_running!
    update!(status: "running", started_at: Time.current, error: nil)
  end

  def record_result!(result, finished_at: Time.current)
    update!(
      status: result.success? ? "succeeded" : "failed",
      finished_at:,
      error: result.error
    )
  end

  def to_partial_path
    "sync_runs/sync_run_item"
  end
end
