class IndexerApp < ApplicationRecord
  belongs_to :indexer
  belongs_to :arr_app

  validates :indexer_id, uniqueness: { scope: :arr_app_id }
end
