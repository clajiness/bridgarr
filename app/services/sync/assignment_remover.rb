module Sync
  class AssignmentRemover
    Result = Data.define(:success?, :message, :error)

    def self.call(indexer_app:, delete_client: Arr::IndexerDeleteClient)
      new(indexer_app:, delete_client:).call
    end

    def initialize(indexer_app:, delete_client:)
      @indexer_app = indexer_app
      @delete_client = delete_client
    end

    def call
      indexer_app.with_lock do
        return failure("Wait for the active assignment sync to finish before removing it.") if indexer_app.active_sync?

        if indexer_app.remote_indexer_id.present?
          delete_result = delete_client.call(
            arr_app: indexer_app.arr_app,
            remote_indexer_id: indexer_app.remote_indexer_id
          )
          return failure(delete_result.message) unless delete_result.success?
        end

        label = "#{indexer_app.indexer.name} → #{indexer_app.arr_app.name}"
        indexer_app.destroy!
        Result.new(success?: true, message: "Removed assignment #{label}.", error: nil)
      end
    end

    private

      attr_reader :indexer_app, :delete_client

      def failure(message)
        message = Secrets::Redactor.call(message)
        Result.new(success?: false, message:, error: message)
      end
  end
end
