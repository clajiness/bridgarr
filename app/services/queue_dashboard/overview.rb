module QueueDashboard
  class Overview
    DEFAULT_PAGE_SIZE = 50
    PAGE_SIZE_OPTIONS = [ 10, 25, 50, 100 ].freeze
    TASK_HISTORY_LIMIT = 10
    FUTURE_RUN_COUNT = 5

    Task = Data.define(:key, :label, :handler, :schedule, :queue_name, :registered, :next_runs, :past_runs)
    Run = Data.define(:run_at, :status, :enqueued_at, :finished_at, :error)
    Job = Data.define(:id, :class_name, :queue_name, :status, :enqueued_at, :scheduled_at, :finished_at, :error)
    Process = Data.define(:kind, :name, :hostname, :last_heartbeat_at, :active)

    attr_reader :now, :error, :current_page, :per_page, :total_job_count, :total_pages

    def initialize(now: Time.current, page: 1, per_page: DEFAULT_PAGE_SIZE)
      @now = now
      @requested_page = positive_integer(page) || 1
      @per_page = allowed_page_size(per_page)
      @current_page = @requested_page
      @total_job_count = 0
      @total_pages = 1
      load_queue_data
    end

    def available?
      @available
    end

    def recurring_tasks
      @recurring_tasks || []
    end

    def recent_jobs
      @recent_jobs || []
    end

    def processes
      @processes || []
    end

    def queued_count
      @queued_count || 0
    end

    def scheduled_count
      @scheduled_count || 0
    end

    def blocked_count
      @blocked_count || 0
    end

    def running_count
      @running_count || 0
    end

    def failed_count
      @failed_count || 0
    end

    def active_worker_count
      processes.count { |process| process.kind == "worker" && process.active }
    end

    def previous_page?
      current_page > 1
    end

    def next_page?
      current_page < total_pages
    end

    def first_job_number
      return 0 if total_job_count.zero?

      ((current_page - 1) * per_page) + 1
    end

    def last_job_number
      [ current_page * per_page, total_job_count ].min
    end

    private

      QUEUE_MODELS = [
        SolidQueue::Job,
        SolidQueue::RecurringTask,
        SolidQueue::RecurringExecution,
        SolidQueue::ReadyExecution,
        SolidQueue::ClaimedExecution,
        SolidQueue::FailedExecution,
        SolidQueue::BlockedExecution,
        SolidQueue::ScheduledExecution,
        SolidQueue::Process
      ].freeze

      JOB_EXECUTION_ASSOCIATIONS = %i[
        failed_execution
        claimed_execution
        blocked_execution
        scheduled_execution
        ready_execution
      ].freeze

      def load_queue_data
        unless queue_tables_available?
          @available = false
          @error = "Solid Queue tables are not available in this environment."
          return
        end

        @available = true
        load_counts
        load_processes
        load_recent_jobs
        load_recurring_tasks
      rescue ActiveRecord::ActiveRecordError => e
        @available = false
        @error = Secrets::Redactor.call("Could not read Solid Queue: #{e.message}")
      end

      def queue_tables_available?
        QUEUE_MODELS.all?(&:table_exists?)
      end

      def load_counts
        @queued_count = SolidQueue::ReadyExecution.count
        @scheduled_count = SolidQueue::ScheduledExecution.count
        @blocked_count = SolidQueue::BlockedExecution.count
        @running_count = SolidQueue::ClaimedExecution.count
        @failed_count = SolidQueue::FailedExecution.count
      end

      def load_processes
        threshold = SolidQueue.process_alive_threshold.ago(now)
        @processes = SolidQueue::Process.order(:kind, :name).map do |process|
          Process.new(
            kind: process.kind,
            name: process.name,
            hostname: process.hostname,
            last_heartbeat_at: process.last_heartbeat_at,
            active: process.last_heartbeat_at >= threshold
          )
        end
      end

      def load_recent_jobs
        scope = SolidQueue::Job
          .includes(*JOB_EXECUTION_ASSOCIATIONS)
          .order(created_at: :desc, id: :desc)

        @total_job_count = scope.count
        @total_pages = [ (@total_job_count.to_f / per_page).ceil, 1 ].max
        @current_page = [ @requested_page, @total_pages ].min

        jobs = scope
          .offset((current_page - 1) * per_page)
          .limit(per_page)

        @recent_jobs = jobs.map { |job| build_job(job) }
      end

      def positive_integer(value)
        integer = Integer(value, exception: false)
        integer if integer&.positive?
      end

      def allowed_page_size(value)
        requested_size = positive_integer(value)
        PAGE_SIZE_OPTIONS.include?(requested_size) ? requested_size : DEFAULT_PAGE_SIZE
      end

      def load_recurring_tasks
        registered_tasks = SolidQueue::RecurringTask.order(:key).index_by(&:key)
        configured_tasks = configured_recurring_tasks.index_by(&:key)
        tasks = configured_tasks.merge(registered_tasks)
        executions = recurring_executions_for(tasks.keys)

        @recurring_tasks = tasks.values.sort_by(&:key).map do |task|
          Task.new(
            key: task.key,
            label: task.key.to_s.humanize,
            handler: task.class_name.presence || "Command",
            schedule: task.schedule,
            queue_name: task.queue_name.presence || "default",
            registered: registered_tasks.key?(task.key),
            next_runs: future_runs(task.schedule),
            past_runs: executions.fetch(task.key, []).first(TASK_HISTORY_LIMIT).map { |execution| build_run(execution) }
          )
        end
      end

      def configured_recurring_tasks
        path = Rails.root.join(ENV.fetch("SOLID_QUEUE_RECURRING_SCHEDULE", "config/recurring.yml"))
        return [] unless path.exist?

        config = ActiveSupport::ConfigurationFile.parse(path).deep_symbolize_keys
        environment_config = config.fetch(Rails.env.to_sym, {})

        environment_config.filter_map do |key, options|
          next unless options.is_a?(Hash) && options[:schedule].present?

          SolidQueue::RecurringTask.from_configuration(key, **options.merge(static: true))
        end
      rescue StandardError => e
        Rails.logger.warn({ message: "Could not read recurring job configuration", error: Secrets::Redactor.call(e.message) })
        []
      end

      def recurring_executions_for(task_keys)
        return {} if task_keys.empty?

        SolidQueue::RecurringExecution
          .where(task_key: task_keys)
          .includes(job: JOB_EXECUTION_ASSOCIATIONS)
          .order(run_at: :desc)
          .to_a
          .group_by(&:task_key)
      end

      def future_runs(schedule)
        cron = Fugit.parse(schedule, multi: :fail)
        cursor = now

        FUTURE_RUN_COUNT.times.map do
          cron.next_time(cursor).to_utc_time.tap { |run_at| cursor = run_at + 1.second }
        end
      rescue ArgumentError, NoMethodError
        []
      end

      def build_run(execution)
        job = execution.job
        Run.new(
          run_at: execution.run_at,
          status: job ? job_status(job) : "archived",
          enqueued_at: job&.created_at,
          finished_at: job&.finished_at,
          error: job_error(job)
        )
      end

      def build_job(job)
        Job.new(
          id: job.id,
          class_name: job.class_name,
          queue_name: job.queue_name,
          status: job_status(job),
          enqueued_at: job.created_at,
          scheduled_at: job.scheduled_at,
          finished_at: job.finished_at,
          error: job_error(job)
        )
      end

      def job_status(job)
        return "finished" if job.finished_at.present?
        return "failed" if job.failed_execution.present?
        return "running" if job.claimed_execution.present?
        return "blocked" if job.blocked_execution.present?
        return "scheduled" if job.scheduled_execution.present?
        return "queued" if job.ready_execution.present?

        "unknown"
      end

      def job_error(job)
        Secrets::Redactor.call(job&.failed_execution&.message)
      rescue StandardError
        "Failure details could not be read."
      end
  end
end
