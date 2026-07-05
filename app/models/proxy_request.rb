class ProxyRequest < ApplicationRecord
  belongs_to :indexer, optional: true

  validates :jackett_id, :request_type, presence: true
  validates :duration_ms, numericality: { greater_than_or_equal_to: 0 }

  scope :recent, -> { order(created_at: :desc) }
  scope :successful, -> { where(http_status: 200..399).where(error: [ nil, "" ]) }
  scope :failed, -> { where("http_status >= ? OR error IS NOT NULL AND error != ''", 400) }

  def successful?
    error.blank? && http_status.to_i.between?(200, 399)
  end

  def failed?
    !successful?
  end
end
