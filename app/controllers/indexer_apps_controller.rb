class IndexerAppsController < ApplicationController
  before_action :set_indexer_app, only: %i[ edit update destroy sync repair forget_remote diagnostic ]

  def index
    @arr_apps = ArrApp.order(:name).to_a
    @indexers_page = Pagination::Page.new(
      collection: filtered_indexers,
      page: params[:page],
      per_page: params[:per_page]
    )
    @indexers = @indexers_page.records
    @assignments_by_cell = IndexerApp
      .includes(:indexer, :arr_app)
      .where(indexer_id: @indexers.map(&:id), arr_app_id: @arr_apps.map(&:id))
      .index_by { |assignment| [ assignment.indexer_id, assignment.arr_app_id ] }
  end

  def edit
  end

  def update
    if @indexer_app.update(indexer_app_params)
      redirect_to indexer_app_redirect_path(@indexer_app), notice: "Assignment settings saved.", status: :see_other
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    result = Sync::AssignmentRemover.call(indexer_app: @indexer_app)

    if result.success?
      redirect_to indexer_apps_path, notice: result.message, status: :see_other
    else
      redirect_to indexer_apps_path, alert: result.message, status: :see_other
    end
  end

  def sync
    unless @indexer_app.enabled?
      return redirect_to(
        preview_indexer_apps_path(assignment_ids: [ @indexer_app.id ]),
        alert: "Disabled assignments must be previewed and explicitly confirmed before remote search modes are changed.",
        status: :see_other
      )
    end

    result = Sync::AssignmentSync.call(indexer_app: @indexer_app)
    notice = result.created? ? "Assignment sync queued." : "Assignment sync is already queued."

    redirect_to sync_run_path(result.sync_run), notice:
  end

  def bulk_update
    cells = selected_cells
    return redirect_to(matrix_return_path, alert: "Select at least one matrix cell.") if cells.empty?

    action = params[:bulk_action].to_s
    if action.in?(%w[preview test sync])
      return run_selected_action(action, cells)
    end

    result = Sync::AssignmentBulkUpdate.call(
      cells:,
      action:,
      category_mode: params[:category_mode],
      custom_categories: params[:custom_categories]
    )
    if result.success?
      redirect_to matrix_return_path, notice: result.message
    else
      redirect_to matrix_return_path, alert: result.message
    end
  end

  def preview
    scope = preview_scope
    @plan = Sync::Plan.call(scope:)
    Sync::PlanRecorder.call(@plan)
  end

  def apply_plan
    assignment_ids = normalized_ids(params[:assignment_ids])
    scope = IndexerApp.where(id: assignment_ids)
    plan = Sync::Plan.call(scope:)
    Sync::PlanRecorder.call(plan)
    result = Sync::PlanApplier.call(
      plan:,
      assignment_ids:,
      expected_digests: expected_plan_digests(assignment_ids),
      destructive_confirmation: params[:confirm_destructive] == "1"
    )

    if result.success?
      redirect_to sync_run_path(result.sync_run), notice: result.message
    else
      failure_path = assignment_ids.any? ? preview_indexer_apps_path(assignment_ids:) : indexer_apps_path
      redirect_to failure_path, alert: result.message, status: :see_other
    end
  end

  def revert_plan
    assignment_ids, requests = desired_state_revert_requests
    if assignment_ids.empty?
      return redirect_to(
        preview_return_path(assignment_ids),
        alert: "Choose at least one local desired-state change to revert.",
        status: :see_other
      )
    end

    plan = Sync::Plan.call(scope: IndexerApp.where(id: assignment_ids))
    Sync::PlanRecorder.call(plan)
    result = Sync::DesiredStateReverter.call(
      plan:,
      requests:,
      expected_digests: expected_plan_digests(assignment_ids)
    )

    redirect_to(
      preview_return_path(assignment_ids),
      result.success? ? { notice: result.message, status: :see_other } : { alert: result.message, status: :see_other }
    )
  end

  def repair
    return redirect_assignment_syncing if @indexer_app.active_sync?

    remote_indexer_id = positive_integer(params.expect(:remote_indexer_id))
    plan = Sync::Plan.call(scope: IndexerApp.where(id: @indexer_app.id))
    Sync::PlanRecorder.call(plan)
    item = plan.items.find { |candidate| candidate.indexer_app.id == @indexer_app.id }

    unless remote_indexer_id && item&.state == "conflict" && item.remote_indexer_id.to_i == remote_indexer_id
      return redirect_to(
        preview_indexer_apps_path(assignment_ids: [ @indexer_app.id ]),
        alert: "The remote conflict changed. Review the refreshed plan before repairing it.",
        status: :see_other
      )
    end

    repaired = @indexer_app.with_lock do
      next false if @indexer_app.active_sync?

      @indexer_app.update!(remote_indexer_id:, last_plan_state: nil)
      true
    end
    return redirect_assignment_syncing unless repaired

    unless @indexer_app.enabled?
      return redirect_to(
        preview_indexer_apps_path(assignment_ids: [ @indexer_app.id ]),
        notice: "Remote association repaired. Review and confirm the disabled desired state before applying it.",
        status: :see_other
      )
    end

    result = Sync::AssignmentSync.call(indexer_app: @indexer_app)

    redirect_to sync_run_path(result.sync_run), notice: "Remote association repaired; reconciliation queued."
  end

  def forget_remote
    return redirect_assignment_syncing if @indexer_app.active_sync?

    forgotten = @indexer_app.with_lock do
      next false if @indexer_app.active_sync?

      @indexer_app.update!(
        remote_indexer_id: nil,
        last_plan_state: nil,
        last_remote_digest: nil,
        last_status: nil,
        last_error: nil
      )
      true
    end
    return redirect_assignment_syncing unless forgotten

    redirect_to preview_indexer_apps_path(assignment_ids: [ @indexer_app.id ]), notice: "Forgot the stale remote association. Review the new plan."
  end

  def diagnostic
    send_data(
      Diagnostics::AssignmentReport.call(indexer_app: @indexer_app),
      filename: "bridgarr-assignment-#{@indexer_app.id}-diagnostic.txt",
      type: "text/plain",
      disposition: "inline"
    )
  end

  private

    def set_indexer_app
      @indexer_app = IndexerApp.includes(:indexer, :arr_app).find(params.expect(:id))
    end

    def indexer_app_params
      params.expect(indexer_app: [ :enabled, :connection_mode, :category_mode, :custom_categories ])
    end

    def indexer_app_redirect_path(indexer_app)
      case params[:return_to]
      when "arr_app" then arr_app_path(indexer_app.arr_app)
      when "matrix" then indexer_apps_path
      when "dashboard" then root_path
      when "preview" then preview_indexer_apps_path(assignment_ids: [ indexer_app.id ])
      else indexer_path(indexer_app.indexer)
      end
    end

    def selected_cells
      Array(params[:cells]).filter_map do |cell|
        indexer_id, arr_app_id = cell.to_s.split(":", 2).map { |value| positive_integer(value) }
        [ indexer_id, arr_app_id ] if indexer_id && arr_app_id
      end.uniq
    end

    def run_selected_action(action, cells)
      assignment_ids = selected_assignment_ids(cells)
      if assignment_ids.empty?
        return redirect_to matrix_return_path, alert: "The selected cells do not have assignments yet. Create them before previewing or syncing."
      end

      redirect_to preview_indexer_apps_path(assignment_ids:),
        notice: ("Review and apply the selected reconciliation plan before syncing." if action == "sync")
    end

    def selected_assignment_ids(cells)
      selected_pairs = cells.to_h { |cell| [ cell, true ] }
      IndexerApp
        .where(indexer_id: cells.map(&:first), arr_app_id: cells.map(&:last))
        .filter_map do |assignment|
          assignment.id if selected_pairs.key?([ assignment.indexer_id, assignment.arr_app_id ])
        end
    end

    def preview_scope
      return IndexerApp.all unless params.key?(:assignment_ids)

      ids = normalized_ids(params[:assignment_ids])
      IndexerApp.where(id: ids)
    end

    def normalized_ids(values)
      Array(values).filter_map { |value| positive_integer(value) }.uniq
    end

    def positive_integer(value)
      parsed = Integer(value.to_s, 10, exception: false)
      parsed if parsed&.positive?
    end

    def expected_plan_digests(assignment_ids)
      submitted_digests = params[:expected_digests]
      return {} unless submitted_digests.respond_to?(:permit)

      submitted_digests.permit(*assignment_ids.map(&:to_s)).to_h
    end

    def desired_state_revert_requests
      if params[:revert_all] == "1"
        ids = normalized_ids(params[:revert_assignment_ids])
        return [ ids, ids.index_with { [ "all" ] } ]
      end

      assignment_id, option_key = params[:revert_target].to_s.split(":", 2)
      assignment_id = positive_integer(assignment_id)
      return [ [], {} ] unless assignment_id && option_key.present?

      [ [ assignment_id ], { assignment_id => [ option_key ] } ]
    end

    def preview_return_path(fallback_assignment_ids)
      return preview_indexer_apps_path if params[:preview_scope] == "all"

      assignment_ids = normalized_ids(params[:preview_assignment_ids])
      assignment_ids = fallback_assignment_ids if assignment_ids.empty?
      preview_indexer_apps_path(assignment_ids:)
    end

    def redirect_assignment_syncing
      redirect_to(
        preview_indexer_apps_path(assignment_ids: [ @indexer_app.id ]),
        alert: "Wait for the active assignment sync to finish before changing its remote association.",
        status: :see_other
      )
    end

    def filtered_indexers
      indexers = Indexer.includes(:indexer_apps).order(:name).to_a
      arr_app_count = ArrApp.count
      case params[:filter]
      when "unassigned"
        indexers.select { |indexer| indexer.indexer_apps.size < arr_app_count }
      when "unhealthy"
        indexers.select { |indexer| indexer.last_status == "error" || indexer.indexer_apps.any? { |assignment| assignment.last_status == "error" } }
      when "unsynced", "never_synced"
        indexers.select { |indexer| indexer.indexer_apps.any? { |assignment| assignment.last_synced_at.nil? } }
      when "failed"
        indexers.select { |indexer| indexer.indexer_apps.any? { |assignment| assignment.last_status.in?(%w[error mismatch]) } }
      when "direct", "bridged"
        indexers.select { |indexer| indexer.indexer_apps.any? { |assignment| assignment.connection_mode == params[:filter] } }
      when "disabled"
        indexers.select { |indexer| !indexer.enabled? || indexer.indexer_apps.any? { |assignment| !assignment.enabled? } }
      when "changed_in_jackett"
        indexers.select { |indexer| indexer.jackett_state.in?(%w[renamed changed disabled]) }
      when "missing_from_jackett"
        indexers.select { |indexer| indexer.jackett_state == "missing" }
      when "orphaned"
        indexers.select { |indexer| indexer.indexer_apps.any? { |assignment| assignment.last_plan_state == "orphaned" } }
      else
        indexers
      end
    end

    def matrix_return_path
      indexer_apps_path(filter: params[:filter], page: params[:page], per_page: params[:per_page])
    end
end
