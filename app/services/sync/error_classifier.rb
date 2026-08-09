module Sync
  class ErrorClassifier
    Result = Data.define(:kind, :summary, :recommendation, :retryable?)

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
        elsif stale_plan?
          "stale_plan"
        elsif remote_conflict?
          "remote_conflict"
        elsif orphaned?
          "orphaned"
        elsif authentication?
          "authentication"
        elsif challenge_solver_timeout?
          "challenge_solver_timeout"
        elsif destination_database_busy?
          "destination_database_busy"
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

      Result.new(kind:, summary: summary_for(kind), recommendation: recommendation_for(kind), retryable?: retryable?(kind))
    end

    private

      attr_reader :message, :skipped

      def incompatible_categories?
        message.match?(/no compatible default categories|does not expose .*compatible torznab categories/i)
      end

      def stale_plan?
        message.match?(/reconciliation plan changed|reviewed assignment no longer exists|preview changed/i)
      end

      def remote_conflict?
        message.match?(/overlapping unmanaged indexer|potentially overlapping indexer|repair the association/i)
      end

      def orphaned?
        message.match?(/remote indexer id .* no longer exists|stale remote association/i)
      end

      def authentication?
        message.match?(/\b(401|403)\b|unauthorized|forbidden|authentication|invalid api key|api key is invalid/i)
      end

      def challenge_solver_timeout?
        return false unless message.match?(/flaresolverr|byparr|anti-bot|cloudflare|challenge/i)

        message.match?(/timeout|timed out|unable to process|error solving|challenge/i)
      end

      def timeout?
        message.match?(/timeout|timed out|Net::ReadTimeout|execution expired/i)
      end

      def destination_database_busy?
        message.match?(/database (?:table )?is locked|\bSQLITE_(?:BUSY|LOCKED)(?:_[A-Z_]+)?\b/i)
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
        %w[challenge_solver_timeout timeout destination_database_busy unavailable network].include?(kind)
      end

      def summary_for(kind)
        case kind
        when "challenge_solver_timeout"
          "The anti-bot challenge solver could not complete the indexer request before the validation timeout."
        when "timeout"
          "Indexer validation timed out. The upstream indexer may be slow or unavailable."
        when "unavailable"
          "The upstream indexer or Jackett endpoint was unavailable during validation."
        when "destination_database_busy"
          "The destination Arr application's database was temporarily busy."
        when "category_mismatch"
          "The app's validation search returned no releases in the selected categories."
        when "incompatible_categories"
          "This assignment is not applicable because the app defaults do not overlap with this indexer."
        when "authentication"
          "Authentication failed. Check the relevant API key or credentials."
        when "stale_plan"
          "The reviewed reconciliation plan changed before Bridgarr could apply it."
        when "remote_conflict"
          "A remote indexer overlaps this assignment but is not safely associated with it."
        when "orphaned"
          "The assignment points to a remote indexer that no longer exists."
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

      def recommendation_for(kind)
        case kind
        when "challenge_solver_timeout", "timeout", "unavailable"
          "Retry the assignment. If it fails again, test the Jackett indexer and increase timeouts only after confirming the upstream service is healthy."
        when "destination_database_busy"
          "Retry after the destination application becomes idle. If this recurs, check for competing app instances, background database work, or a database stored on network storage."
        when "category_mismatch"
          "Retry the assignment once. If it still finds no releases, review its category settings before changing them."
        when "incompatible_categories"
          "Review the assignment's category mode and select compatible or custom categories."
        when "authentication"
          "Edit and retest the affected application or Jackett API key."
        when "stale_plan"
          "Preview reconciliation again, review the refreshed differences, and apply the new plan."
        when "remote_conflict"
          "Preview reconciliation and explicitly repair the remote association before syncing."
        when "orphaned"
          "Preview reconciliation, then forget the stale association or repair it to the correct remote indexer."
        when "invalid_configuration"
          "Open assignment settings, correct the rejected value, and preview reconciliation again."
        when "network"
          "Verify container DNS, hostnames, ports, and network routes, then retest the affected service."
        when "search_failed"
          "Test the indexer in Jackett and review the validation details returned by the destination application."
        else
          "Retry once, then copy the diagnostic report and include it when opening an issue."
        end
      end
  end
end
