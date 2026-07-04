module Sync
  class IndexerAppSync
    Result = Data.define(:success?, :remote_indexer_id, :message, :error)

    REMOTE_NAME_SUFFIX = " (Bridgarr)"

    def self.call(indexer_app:, client: Arr::GenericTorznabClient)
      new(indexer_app:, client:).call
    end

    def initialize(indexer_app:, client:)
      @indexer_app = indexer_app
      @client = client
    end

    def call
      return record(failure("Enable #{indexer.name} before syncing.")) unless indexer.enabled?
      return record(failure("Enable #{arr_app.name} before syncing.")) unless arr_app.enabled?
      return failure("This assignment is already synced. Updating remote indexers is not implemented yet.") if indexer_app.remote_indexer_id.present?

      result = client.call(
        arr_app:,
        name: remote_indexer_name,
        jackett_base_url: Setting.fetch_value(Setting::JACKETT_BASE_URL_KEY),
        jackett_api_key: Setting.fetch_value(Setting::JACKETT_API_KEY_KEY),
        jackett_id: indexer.jackett_id
      )

      if result.success?
        record(success(result.remote_indexer_id))
      else
        record(failure(result.message))
      end
    end

    private

      attr_reader :indexer_app, :client

      delegate :indexer, :arr_app, to: :indexer_app

      def record(result)
        indexer_app.record_sync_result(result)
        result
      end

      def success(remote_indexer_id)
        Result.new(
          success?: true,
          remote_indexer_id:,
          message: "#{indexer.name} synced to #{arr_app.name}.",
          error: nil
        )
      end

      def failure(message)
        Result.new(success?: false, remote_indexer_id: nil, message:, error: message)
      end

      def remote_indexer_name
        return indexer.name if indexer.name.end_with?(REMOTE_NAME_SUFFIX)

        "#{indexer.name}#{REMOTE_NAME_SUFFIX}"
      end
  end
end
