class Indexer < ApplicationRecord
  JACKETT_ID_FORMAT = /\A[a-zA-Z0-9][a-zA-Z0-9._-]*\z/

  has_many :indexer_apps, dependent: :destroy
  has_many :arr_apps, through: :indexer_apps

  validates :name, :jackett_id, presence: true
  validates :jackett_id, uniqueness: true
  validates :jackett_id, format: { with: JACKETT_ID_FORMAT, message: "must be a Jackett ID or Jackett Torznab URL" }

  normalizes :jackett_id, with: ->(jackett_id) { Jackett::IndexerIdParser.call(jackett_id) }
end
