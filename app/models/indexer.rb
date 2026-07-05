class Indexer < ApplicationRecord
  JACKETT_ID_FORMAT = /\A[a-zA-Z0-9][a-zA-Z0-9._-]*\z/

  has_many :indexer_apps, dependent: :destroy
  has_many :arr_apps, through: :indexer_apps
  has_many :proxy_requests, dependent: :nullify

  validates :name, :jackett_id, presence: true
  validates :jackett_id, uniqueness: true
  validates :jackett_id, format: { with: JACKETT_ID_FORMAT, message: "must be a Jackett ID or Jackett Torznab URL" }

  normalizes :jackett_id, with: ->(jackett_id) { Jackett::IndexerIdParser.call(jackett_id) }

  def proxy_activity_stats(since: 24.hours.ago)
    scoped_requests = proxy_requests.where(created_at: since..)

    {
      total: scoped_requests.count,
      successful: scoped_requests.successful.count,
      failed: scoped_requests.failed.count,
      downloads: scoped_requests.where(request_type: "download").count,
      average_duration_ms: scoped_requests.average(:duration_ms).to_i,
      last_request: proxy_requests.recent.first
    }
  end
end
