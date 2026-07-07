module Sync
  class ErrorClassifier
    Result = Data.define(:kind, :summary, :retryable?)

    def self.call(message, skipped: false)
      new(message, skipped:).call
    end

    def initialize(message, skipped:)
      @message = Secrets::Redactor.call(message).to_s
      @skipped = skipped
    end

    def call
      kind =
        if skipped || incompatible_categories?
          "incompatible_categories"
        elsif authentication?
          "authentication"
        elsif timeout?
          "timeout"
        elsif unavailable?
          "unavailable"
        elsif category_mismatch?
          "category_mismatch"
        elsif invalid_configuration?
          "invalid_configuration"
        elsif network?
          "network"
        elsif search_failed?
          "search_failed"
        else
          "unknown"
        end

      Result.new(kind:, summary: summary_for(kind), retryable?: retryable?(kind))
    end

    private

      attr_reader :message, :skipped

      def incompatible_categories?
        message.match?(/no compatible default categories|does not expose .*compatible torznab categories/i)
      end

      def authentication?
        message.match?(/\b(401|403)\b|unauthorized|forbidden|authentication|invalid api key|api key is invalid/i)
      end

      def timeout?
        message.match?(/timeout|timed out|Net::ReadTimeout|execution expired/i)
      end

      def unavailable?
        message.match?(/server is unavailable|try again later|\b(502|503|504)\b|bad gateway|service unavailable|gateway timeout/i)
      end

      def category_mismatch?
        message.match?(/configured categories were returned|category settings|returned releases did not contain/i)
      end

      def invalid_configuration?
        message.match?(/missing|required|malformed|invalid url|did not return a generic torznab schema|unsupported|schema/i)
      end

      def network?
        message.match?(/could not connect|connection refused|network|no route to host|host unreachable|getaddrinfo/i)
      end

      def search_failed?
        message.match?(/validation|query successful|jackett rejected|badrequest|http 400/i)
      end

      def retryable?(kind)
        %w[timeout unavailable network].include?(kind)
      end

      def summary_for(kind)
        case kind
        when "timeout"
          "Indexer validation timed out. The upstream indexer may be slow or unavailable."
        when "unavailable"
          "The upstream indexer or Jackett endpoint was unavailable during validation."
        when "category_mismatch"
          "The indexer responded, but returned releases did not match the selected categories."
        when "incompatible_categories"
          "This assignment was skipped because the app defaults do not overlap with this indexer."
        when "authentication"
          "Authentication failed. Check the relevant API key or credentials."
        when "invalid_configuration"
          "The indexer configuration was rejected or incomplete."
        when "network"
          "Bridgarr could not reach the app, Jackett, or upstream indexer."
        when "search_failed"
          "The app reached the indexer, but validation search failed."
        else
          "The sync failed for an unknown reason."
        end
      end
  end
end
