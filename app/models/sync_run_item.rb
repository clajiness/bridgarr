class SyncRunItem < ApplicationRecord
  STATUSES = %w[queued running succeeded failed skipped].freeze

  belongs_to :sync_run
  belongs_to :indexer_app, optional: true

  validates :status, inclusion: { in: STATUSES }

  scope :ordered, -> { order(:indexer_name, :arr_app_name, :id) }

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
