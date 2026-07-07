module Sync
  class IndexerAppSync
    Result = Struct.new(:success?, :skipped?, :remote_indexer_id, :message, :error, keyword_init: true)

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

      result = client.call(
        arr_app:,
        name: remote_indexer_name,
        bridgarr_base_url: Setting.fetch_value(Setting::BRIDGARR_BASE_URL_KEY),
        jackett_base_url: Setting.fetch_value(Setting::JACKETT_BASE_URL_KEY),
        jackett_api_key: Setting.fetch_value(Setting::JACKETT_API_KEY_KEY),
        jackett_id: indexer.jackett_id,
        remote_indexer_id: indexer_app.remote_indexer_id,
        connection_mode: indexer_app.connection_mode,
        category_mode: indexer_app.category_mode,
        custom_category_ids: indexer_app.custom_category_ids
      )

      if result.success?
        record(success(result.remote_indexer_id, result.message))
      elsif result.skipped?
        record(skipped(result.message))
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

      def success(remote_indexer_id, client_message)
        Result.new(
          success?: true,
          skipped?: false,
          remote_indexer_id:,
          message: success_message(client_message),
          error: nil
        )
      end

      def skipped(message)
        Result.new(success?: false, skipped?: true, remote_indexer_id: nil, message:, error: message)
      end

      def failure(message)
        Result.new(success?: false, skipped?: false, remote_indexer_id: nil, message:, error: message)
      end

      def remote_indexer_name
        return indexer.name if indexer.name.end_with?(REMOTE_NAME_SUFFIX)

        "#{indexer.name}#{REMOTE_NAME_SUFFIX}"
      end

      def success_message(client_message)
        case client_message
        when "Generic Torznab indexer is already synced."
          "#{indexer.name} is already synced to #{arr_app.name}."
        when "Generic Torznab indexer already exists."
          "#{indexer.name} was already present in #{arr_app.name}; Bridgarr adopted it."
        when /^Generic Torznab indexer exists after/
          "#{indexer.name} synced to #{arr_app.name} after #{arr_app.name} timed out."
        else
          "#{indexer.name} synced to #{arr_app.name}."
        end
      end
  end
end
