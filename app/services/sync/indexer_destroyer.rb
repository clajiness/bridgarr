module Sync
  class IndexerDestroyer
    Result = Data.define(:success?, :message, :error)

    def self.call(indexer:, delete_client: Arr::IndexerDeleteClient)
      new(indexer:, delete_client:).call
    end

    def initialize(indexer:, delete_client:)
      @indexer = indexer
      @delete_client = delete_client
    end

    def call
      delete_remote_indexers.each do |result|
        return failure(result.message) unless result.success?
      end

      indexer.destroy!
      success
    end

    private

      attr_reader :indexer, :delete_client

      def delete_remote_indexers
        synced_assignments.map do |assignment|
          delete_client.call(arr_app: assignment.arr_app, remote_indexer_id: assignment.remote_indexer_id)
        end
      end

      def synced_assignments
        indexer.indexer_apps.includes(:arr_app).where.not(remote_indexer_id: nil)
      end

      def success
        Result.new(success?: true, message: "Indexer removed.", error: nil)
      end

      def failure(message)
        Result.new(success?: false, message:, error: message)
      end
  end
end
