module Bridgarr
  class BuildInfo
    DEFAULT_VERSION = "development"
    DEFAULT_COMMIT_SHA = "unknown"
    DEFAULT_BUILD_DATE = "unknown"

    def self.current
      new
    end

    def self.log_startup!(logger: Rails.logger)
      current.log_startup!(logger:)
    end

    def version
      ENV.fetch("BRIDGARR_VERSION", DEFAULT_VERSION).presence || DEFAULT_VERSION
    end

    def commit_sha
      ENV.fetch("BRIDGARR_COMMIT_SHA", DEFAULT_COMMIT_SHA).presence || DEFAULT_COMMIT_SHA
    end

    def short_commit_sha
      return commit_sha if commit_sha == DEFAULT_COMMIT_SHA

      commit_sha.first(12)
    end

    def build_date
      ENV.fetch("BRIDGARR_BUILD_DATE", DEFAULT_BUILD_DATE).presence || DEFAULT_BUILD_DATE
    end

    def to_h
      {
        version:,
        commit_sha:,
        short_commit_sha:,
        build_date:
      }
    end

    def log_startup!(logger:)
      logger.info(
        {
          message: "Booted Bridgarr",
          bridgarr_version: version,
          bridgarr_commit_sha: commit_sha,
          bridgarr_build_date: build_date
        }
      )
    end
  end
end
