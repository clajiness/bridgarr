module Arr
  class ApiRoutes
    API_VERSION_BY_APP_TYPE = {
      "lidarr" => "v1",
      "other" => "v3",
      "radarr" => "v3",
      "sonarr" => "v3",
      "whisparr" => "v3"
    }.freeze

    def self.for(app_type:)
      new(app_type:)
    end

    def initialize(app_type:)
      @api_version = API_VERSION_BY_APP_TYPE.fetch(app_type.to_s, "v3")
    end

    def status
      "#{prefix}/system/status"
    end

    def indexers
      "#{prefix}/indexer"
    end

    def indexer_schema
      "#{indexers}/schema"
    end

    def indexer(remote_indexer_id)
      "#{indexers}/#{remote_indexer_id}"
    end

    private

      attr_reader :api_version

      def prefix
        "/api/#{api_version}"
      end
  end
end
