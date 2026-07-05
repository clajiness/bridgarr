class IndexerApp < ApplicationRecord
  belongs_to :indexer
  belongs_to :arr_app
  has_many :sync_run_items, dependent: :nullify

  validates :indexer_id, uniqueness: { scope: :arr_app_id }

  def record_sync_result(result, synced_at: Time.current)
    update!(
      remote_indexer_id: result.remote_indexer_id || remote_indexer_id,
      last_synced_at: synced_at,
      last_status: result.success? ? "ok" : "error",
      last_error: result.error
    )
  end
end
