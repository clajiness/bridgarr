require "rails_helper"

RSpec.describe "Indexer app assignments", type: :request do
  let(:arr_app) do
    ArrApp.create!(
      name: "Main Radarr",
      app_type: "radarr",
      base_url: "http://localhost:7878",
      api_key: "radarr-api-key"
    )
  end

  let(:indexer) do
    Indexer.create!(name: "LimeTorrents", jackett_id: "limetorrents")
  end

  let(:assignment) do
    IndexerApp.create!(arr_app:, indexer:)
  end

  it "renders assignment settings" do
    get edit_indexer_app_path(assignment)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Assignment settings")
    expect(response.body).to include("Connection mode")
    expect(response.body).to include("Category mode")
    expect(response.body).to include("Enable RSS")
    expect(response.body).to include("Enable automatic search")
    expect(response.body).to include("Enable interactive search")
    expect(response.body).not_to include("Enabled in the destination app")
    expect(response.body).to include("LimeTorrents")
    expect(response.body).to include("Main Radarr")
  end

  it "renders the centralized assignment matrix" do
    assignment

    get indexer_apps_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Assignment matrix")
    expect(response.body).to include("LimeTorrents")
    expect(response.body).to include("Main Radarr")
    expect(response.body).to include("RSS on", "Automatic on", "Interactive on")
    expect(response.body).to include('data-controller="bulk-actions"')
    expect(response.body).to include("0 cells selected", "Choose a bulk action")
    expect(response.body).not_to include("Apply to selected")

    document = Nokogiri::HTML(response.body)
    bulk_form = document.at_css('form[action="/indexer_apps/bulk_update"]')
    search_modes_panel = bulk_form.at_css('[data-bulk-action="search_modes"]')
    categories_panel = bulk_form.at_css('[data-bulk-action="categories"]')
    submit_button = bulk_form.at_css('[data-bulk-actions-target="submit"]')
    expect(search_modes_panel.key?("hidden")).to be(true)
    expect(categories_panel.key?("hidden")).to be(true)
    expect(submit_button.name).to eq("button")
    expect(submit_button["disabled"]).to eq("disabled")
    expect(response.body).not_to include("manage their desired state")
  end

  it "paginates assignment matrix rows" do
    arr_app
    12.times do |index|
      Indexer.create!(
        name: "Matrix-#{index.to_s.rjust(2, "0")}",
        jackett_id: "matrix-#{index}"
      )
    end

    get indexer_apps_path(page: 2, per_page: 10)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Showing 11–12 of 12 indexers", "Matrix-10", "Matrix-11")
    expect(response.body).not_to include("Matrix-00")
    document = Nokogiri::HTML(response.body)
    bulk_form = document.at_css('form[action="/indexer_apps/bulk_update"]')
    expect(bulk_form.at_css('input[name="page"]')["value"]).to eq("2")
    expect(bulk_form.at_css('input[name="per_page"]')["value"]).to eq("10")
    pagination_form = document.at_css('form[data-controller="autosubmit"]')
    expect(pagination_form.at_css('select[name="per_page"]')["data-action"]).to eq("change->autosubmit#submit")
  end

  it "updates assignment category settings" do
    patch indexer_app_path(assignment), params: {
      indexer_app: {
        connection_mode: "bridged",
        category_mode: "custom",
        custom_categories: "2000, 8000"
      }
    }

    expect(response).to redirect_to(indexer_path(indexer))
    expect(flash[:notice]).to eq("Assignment settings saved.")
    expect(assignment.reload.connection_mode).to eq("bridged")
    expect(assignment.reload.category_mode).to eq("custom")
    expect(assignment.custom_categories).to eq("2000,8000")
  end

  it "updates independent search modes without removing the assignment" do
    patch indexer_app_path(assignment), params: {
      indexer_app: {
        enable_rss: false,
        enable_automatic_search: true,
        enable_interactive_search: false
      }
    }

    expect(response).to redirect_to(indexer_path(indexer))
    expect(assignment.reload).to have_attributes(
      enable_rss: false,
      enable_automatic_search: true,
      enable_interactive_search: false
    )
    expect(IndexerApp.exists?(assignment.id)).to be(true)
  end

  it "creates assignments from selected matrix cells" do
    post bulk_update_indexer_apps_path, params: {
      cells: [ "#{indexer.id}:#{arr_app.id}" ],
      bulk_action: "create"
    }

    expect(response).to redirect_to(indexer_apps_path)
    expect(IndexerApp.find_by(indexer:, arr_app:)).to be_all_search_modes_enabled
  end

  it "bulk updates selected search modes while preserving keep-existing values" do
    assignment.update!(enable_interactive_search: false)

    post bulk_update_indexer_apps_path, params: {
      cells: [ "#{indexer.id}:#{arr_app.id}" ],
      bulk_action: "search_modes",
      enable_rss: "disable",
      enable_automatic_search: "keep",
      enable_interactive_search: "enable"
    }

    expect(response).to redirect_to(preview_indexer_apps_path(assignment_ids: [ assignment.id ]))
    expect(flash[:notice]).to include("Updated 1 assignment", "Review the reconciliation preview")
    expect(assignment.reload).to have_attributes(
      enable_rss: false,
      enable_automatic_search: true,
      enable_interactive_search: true
    )
  end

  it "updates and previews only assigned cells from a mixed selection" do
    unassigned_indexer = Indexer.create!(name: "Unassigned", jackett_id: "unassigned")
    assignment

    post bulk_update_indexer_apps_path, params: {
      cells: [ "#{indexer.id}:#{arr_app.id}", "#{unassigned_indexer.id}:#{arr_app.id}" ],
      bulk_action: "search_modes",
      enable_rss: "disable",
      enable_automatic_search: "keep",
      enable_interactive_search: "keep"
    }

    expect(response).to redirect_to(preview_indexer_apps_path(assignment_ids: [ assignment.id ]))
    expect(flash[:notice]).to include("Updated 1 assignment")
    expect(assignment.reload).not_to be_enable_rss
    expect(IndexerApp.find_by(indexer: unassigned_indexer, arr_app:)).to be_nil
  end

  it "does not claim an existing assignment was created" do
    assignment

    post bulk_update_indexer_apps_path, params: {
      cells: [ "#{indexer.id}:#{arr_app.id}" ],
      bulk_action: "create"
    }

    expect(response).to redirect_to(indexer_apps_path)
    expect(flash[:notice]).to include("No assignments were created", "already assigned")
    expect(IndexerApp.where(indexer:, arr_app:).count).to eq(1)
  end

  it "does not preview every assignment when only unassigned cells were selected" do
    post bulk_update_indexer_apps_path, params: {
      cells: [ "#{indexer.id}:#{arr_app.id}" ],
      bulk_action: "preview"
    }

    expect(response).to redirect_to(indexer_apps_path)
    expect(flash[:alert]).to include("do not have assignments yet")
  end

  it "routes selected sync through preview without queueing remote work" do
    assignment
    allow(Sync::BulkSync).to receive(:call)

    post bulk_update_indexer_apps_path, params: {
      cells: [ "#{indexer.id}:#{arr_app.id}" ],
      bulk_action: "sync"
    }

    expect(response).to redirect_to(preview_indexer_apps_path(assignment_ids: [ assignment.id ]))
    expect(flash[:notice]).to include("Review and apply")
    expect(Sync::BulkSync).not_to have_received(:call)
  end

  it "requires preview before syncing an assignment with a disabled search mode" do
    assignment.update!(enable_automatic_search: false)
    allow(Sync::AssignmentSync).to receive(:call)

    post sync_indexer_app_path(assignment)

    expect(response).to redirect_to(preview_indexer_apps_path(assignment_ids: [ assignment.id ]))
    expect(response).to have_http_status(:see_other)
    expect(flash[:alert]).to include("disabled search modes must be previewed")
    expect(Sync::AssignmentSync).not_to have_received(:call)
  end

  it "rejects unknown matrix actions without changing assignments" do
    assignment

    post bulk_update_indexer_apps_path, params: {
      cells: [ "#{indexer.id}:#{arr_app.id}" ],
      bulk_action: "unknown"
    }

    expect(response).to redirect_to(indexer_apps_path)
    expect(flash[:alert]).to eq("Choose a valid bulk action.")
    expect(assignment.reload).to be_all_search_modes_enabled
  end

  it "returns to the app page when editing from an app" do
    patch indexer_app_path(assignment), params: {
      return_to: "arr_app",
      indexer_app: {
        category_mode: "none"
      }
    }

    expect(response).to redirect_to(arr_app_path(arr_app))
    expect(assignment.reload.category_mode).to eq("none")
  end

  it "returns to the dashboard when editing from the operational table" do
    patch indexer_app_path(assignment), params: {
      return_to: "dashboard",
      indexer_app: { enable_interactive_search: false }
    }

    expect(response).to redirect_to(root_path)
    expect(assignment.reload).not_to be_enable_interactive_search
  end

  it "shows invalid custom category errors" do
    patch indexer_app_path(assignment), params: {
      indexer_app: {
        category_mode: "custom",
        custom_categories: "movies"
      }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("must be a comma-separated list of positive category IDs")
  end

  it "downloads a redacted assignment diagnostic report" do
    assignment.update!(last_status: "error", last_error: "HTTP 401 apikey=secret-value")

    get diagnostic_indexer_app_path(assignment, format: :text)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/plain")
    expect(response.body).to include("Bridgarr assignment diagnostic report")
    expect(response.body).not_to include("secret-value")

    get indexer_apps_path

    diagnostic_control = Nokogiri::HTML(response.body).at_css('[data-controller="clipboard"]')
    inline_report = Base64.strict_decode64(diagnostic_control["data-clipboard-report-value"])
    expect(inline_report).to include("Bridgarr assignment diagnostic report", "Assignment ID: #{assignment.id}")
    expect(inline_report).not_to include("secret-value")
  end

  it "renders a mutation-free reconciliation preview" do
    item = Sync::Plan::Item.new(
      indexer_app: assignment,
      state: "create",
      remote_indexer_id: nil,
      changes: [],
      message: "A managed Generic Torznab indexer will be created.",
      desired_digest: "desired",
      remote_digest: nil,
      plan_digest: "plan",
      destructive: false
    )
    plan = Sync::Plan::Result.new(items: [ item ], generated_at: Time.current)
    allow(Sync::Plan).to receive(:call).and_return(plan)

    get preview_indexer_apps_path(assignment_ids: [ assignment.id ])

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Reconciliation preview")
    expect(response.body).to include("No remote configuration was changed")
    expect(response.body).not_to include("inspection only")
    expect(response.body).to include("Apply selected plan")
    expect(assignment.reload.last_plan_state).to eq("create")
  end

  it "keeps changed assignments visible while collapsing no-change assignments" do
    unchanged_assignment = IndexerApp.create!(
      arr_app:,
      indexer: Indexer.create!(name: "Already matching", jackett_id: "already-matching")
    )
    changed_item = Sync::Plan::Item.new(
      indexer_app: assignment,
      state: "create",
      remote_indexer_id: nil,
      changes: [],
      message: "A managed Generic Torznab indexer will be created.",
      desired_digest: "changed-desired",
      remote_digest: nil,
      plan_digest: "changed-plan",
      destructive: false
    )
    unchanged_item = Sync::Plan::Item.new(
      indexer_app: unchanged_assignment,
      state: "unchanged",
      remote_indexer_id: 42,
      changes: [],
      message: "Remote configuration already matches.",
      desired_digest: "matching-desired",
      remote_digest: "matching-desired",
      plan_digest: "matching-plan",
      destructive: false
    )
    allow(Sync::Plan).to receive(:call).and_return(
      Sync::Plan::Result.new(items: [ changed_item, unchanged_item ], generated_at: Time.current)
    )

    get preview_indexer_apps_path(assignment_ids: [ assignment.id, unchanged_assignment.id ])

    document = Nokogiri::HTML(response.body)
    review_table = document.at_css('table[data-reconciliation-items="review"]')
    no_change_details = document.at_css("details[data-no-change-assignments]")
    expect(review_table.text).to include("LimeTorrents")
    expect(review_table.text).not_to include("Already matching")
    expect(no_change_details.text).to include("Show 1 no-change assignment", "Already matching")
    expect(no_change_details.key?("open")).to be(false)
    expect(document.css('input[name="assignment_ids[]"]').map { |input| input["value"] }).to eq([ assignment.id.to_s ])
  end

  it "clears a persisted false update when Arr masks an unchanged API key" do
    Setting.write_value(Setting::JACKETT_BASE_URL_KEY, "http://localhost:9117")
    Setting.write_value(Setting::JACKETT_API_KEY_KEY, "jackett-api-key")
    assignment.update!(
      remote_indexer_id: 42,
      jackett_api_key_version: Setting.jackett_api_key_version,
      last_status: "ok",
      last_synced_at: 2.hours.ago,
      last_applied_at: 2.hours.ago,
      last_plan_state: "update",
      last_inspected_at: 1.hour.ago
    )
    remote = {
      "id" => 42,
      "name" => "LimeTorrents (Bridgarr)",
      "enableRss" => true,
      "enableAutomaticSearch" => true,
      "enableInteractiveSearch" => true,
      "fields" => [
        { "name" => "baseUrl", "value" => "http://localhost:9117/api/v2.0/indexers/limetorrents/results/torznab" },
        { "name" => "apiPath", "value" => "/api" },
        { "name" => "apiKey", "value" => "********" },
        { "name" => "categories", "value" => [ 2000 ] }
      ]
    }
    schema = {
      "implementation" => "Torznab",
      "configContract" => "TorznabSettings",
      "fields" => [
        { "name" => "baseUrl", "value" => "" },
        { "name" => "apiPath", "value" => "/api" },
        { "name" => "apiKey", "value" => "" },
        { "name" => "categories", "value" => [ 2000 ] }
      ]
    }
    allow(Arr::IndexerInventory).to receive(:call).and_return(
      Arr::IndexerInventory::Result.new(
        success?: true,
        indexers: [ remote ],
        torznab_schema: schema,
        message: "Inspected Main Radarr.",
        error: nil,
        http_status: 200
      )
    )
    allow(Jackett::TorznabCaps).to receive(:call).and_return(
      Jackett::TorznabCaps::Result.new(
        success?: true,
        category_ids: [ 2000 ],
        message: "Found 1 Torznab category.",
        error: nil,
        http_status: 200
      )
    )

    get preview_indexer_apps_path(assignment_ids: [ assignment.id ])

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("No change", "Remote configuration already matches.")
    expect(response.body).not_to include("API key:")
    document = Nokogiri::HTML(response.body)
    expect(document.at_css('input[name="assignment_ids[]"]')).to be_nil
    expect(document.at_css('input[type="submit"][value="Apply selected plan"]')).to be_nil
    expect(response.body).to include("This assignment already matches.", "Nothing needs to be applied.", "Show 1 no-change assignment")
    no_change_details = document.at_css("details[data-no-change-assignments]")
    expect(no_change_details).to be_present
    expect(no_change_details.key?("open")).to be(false)
    expect(no_change_details.at_css('table[data-reconciliation-items="no-change"]')).to be_present
    expect(assignment.reload.last_plan_state).to eq("unchanged")
    expect(Dashboard::Overview.new.assignment_rows.first.status).to eq("healthy")
  end

  it "prominently identifies destructive remote search-mode changes" do
    item = Sync::Plan::Item.new(
      indexer_app: assignment,
      state: "update",
      remote_indexer_id: 42,
      changes: [ { "field" => "enableRss", "label" => "RSS", "current" => "Enabled", "desired" => "Disabled" } ],
      message: "Remote search modes will change.",
      desired_digest: "desired",
      remote_digest: "remote",
      plan_digest: "plan",
      destructive: true
    )
    allow(Sync::Plan).to receive(:call).and_return(Sync::Plan::Result.new(items: [ item ], generated_at: Time.current))

    get preview_indexer_apps_path(assignment_ids: [ assignment.id ])

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("1", "Assignment will have remote search modes disabled")
    expect(response.body).to include("One or more remote search modes will be disabled")
    expect(response.body).to include("Confirm remote search-mode disablement")
    confirmation = Nokogiri::HTML(response.body).at_css('input[name="confirm_destructive"]')
    expect(confirmation).to be_present
    expect(confirmation.attribute("required")).to be_nil
  end

  it "offers field, assignment, and preview rollback controls only for local desired-state changes" do
    assignment.update_column(:last_applied_settings, assignment.desired_settings_snapshot)
    assignment.update!(enable_rss: false, category_mode: "none")
    item = Sync::Plan::Item.new(
      indexer_app: assignment,
      state: "update",
      remote_indexer_id: 42,
      changes: [
        { "field" => "enableRss", "label" => "RSS", "current" => "Enabled", "desired" => "Disabled" },
        { "field" => "categories", "label" => "Categories", "current" => "2000", "desired" => "None" }
      ],
      message: "2 fields will change.",
      desired_digest: "desired",
      remote_digest: "remote",
      plan_digest: "reviewed-plan",
      destructive: true
    )
    allow(Sync::Plan).to receive(:call).and_return(Sync::Plan::Result.new(items: [ item ], generated_at: Time.current))

    get preview_indexer_apps_path(assignment_ids: [ assignment.id ])

    document = Nokogiri::HTML(response.body)
    expect(document.at_css('button[name="revert_target"][value$=":enable_rss"]')).to be_present
    expect(document.at_css('button[name="revert_target"][value$=":categories"]')).to be_present
    expect(document.at_css('button[name="revert_target"][value$=":all"]')).to be_present
    expect(document.at_css('button[name="revert_all"][value="1"]')).to be_present
  end

  it "reverts one reviewed local desired-state change and returns to the same preview scope" do
    assignment.update_column(:last_applied_settings, assignment.desired_settings_snapshot)
    assignment.update!(category_mode: "none")
    item = Sync::Plan::Item.new(
      indexer_app: assignment,
      state: "update",
      remote_indexer_id: 42,
      changes: [ { "field" => "categories", "label" => "Categories", "current" => "2000", "desired" => "None" } ],
      message: "1 field will change.",
      desired_digest: "desired",
      remote_digest: "remote",
      plan_digest: "reviewed-plan",
      destructive: false
    )
    allow(Sync::Plan).to receive(:call).and_return(Sync::Plan::Result.new(items: [ item ], generated_at: Time.current))

    post revert_plan_indexer_apps_path, params: {
      revert_target: "#{assignment.id}:categories",
      expected_digests: { assignment.id.to_s => "reviewed-plan" },
      preview_scope: "selected",
      preview_assignment_ids: [ assignment.id ]
    }

    expect(response).to redirect_to(preview_indexer_apps_path(assignment_ids: [ assignment.id ]))
    expect(flash[:notice]).to include("Reverted 1 local desired-state change")
    expect(assignment.reload.category_mode).to eq("auto")
  end

  it "reverts all reviewed local desired-state changes across the full preview" do
    second_indexer = Indexer.create!(name: "1337x", jackett_id: "1337x")
    second_assignment = IndexerApp.create!(arr_app:, indexer: second_indexer, remote_indexer_id: 43)
    [ assignment, second_assignment ].each do |record|
      record.update_column(:last_applied_settings, record.desired_settings_snapshot)
      record.update!(category_mode: "none")
    end
    items = [ assignment, second_assignment ].map.with_index do |record, index|
      Sync::Plan::Item.new(
        indexer_app: record,
        state: "update",
        remote_indexer_id: record.remote_indexer_id,
        changes: [ { "field" => "categories", "label" => "Categories", "current" => "2000", "desired" => "None" } ],
        message: "1 field will change.",
        desired_digest: "desired-#{index}",
        remote_digest: "remote-#{index}",
        plan_digest: "reviewed-plan-#{index}",
        destructive: false
      )
    end
    allow(Sync::Plan).to receive(:call).and_return(Sync::Plan::Result.new(items:, generated_at: Time.current))

    post revert_plan_indexer_apps_path, params: {
      revert_all: "1",
      revert_assignment_ids: [ assignment.id, second_assignment.id ],
      expected_digests: {
        assignment.id.to_s => "reviewed-plan-0",
        second_assignment.id.to_s => "reviewed-plan-1"
      },
      preview_scope: "all"
    }

    expect(response).to redirect_to(preview_indexer_apps_path)
    expect(flash[:notice]).to include("2 local desired-state changes", "2 assignments")
    expect(assignment.reload.category_mode).to eq("auto")
    expect(second_assignment.reload.category_mode).to eq("auto")
  end

  it "does not expand an explicitly empty preview selection to every assignment" do
    assignment
    allow(Sync::Plan).to receive(:call).and_call_original

    get preview_indexer_apps_path(assignment_ids: [ "invalid" ])

    expect(response).to have_http_status(:ok)
    expect(Sync::Plan).to have_received(:call) do |scope:|
      expect(scope).to be_none
    end
    expect(response.body).not_to include("LimeTorrents")
  end

  it "rechecks and queues an explicitly reviewed reconciliation plan" do
    item = Sync::Plan::Item.new(
      indexer_app: assignment,
      state: "create",
      remote_indexer_id: nil,
      changes: [],
      message: "Create.",
      desired_digest: "desired",
      remote_digest: nil,
      plan_digest: "reviewed-plan",
      destructive: false
    )
    plan = Sync::Plan::Result.new(items: [ item ], generated_at: Time.current)
    allow(Sync::Plan).to receive(:call).and_return(plan)

    post apply_plan_indexer_apps_path, params: {
      assignment_ids: [ assignment.id ],
      expected_digests: { assignment.id.to_s => "reviewed-plan" }
    }

    sync_run = SyncRun.order(:id).last
    expect(response).to redirect_to(sync_run_path(sync_run))
    expect(sync_run.sync_run_items.first.plan_digest).to eq("reviewed-plan")
  end

  it "refuses a destructive plan without server-side confirmation" do
    item = Sync::Plan::Item.new(
      indexer_app: assignment,
      state: "update",
      remote_indexer_id: 42,
      changes: [],
      message: "Disable remote search modes.",
      desired_digest: "desired",
      remote_digest: "remote",
      plan_digest: "reviewed-plan",
      destructive: true
    )
    allow(Sync::Plan).to receive(:call).and_return(Sync::Plan::Result.new(items: [ item ], generated_at: Time.current))

    post apply_plan_indexer_apps_path, params: {
      assignment_ids: [ assignment.id ],
      expected_digests: { assignment.id.to_s => "reviewed-plan" }
    }

    expect(response).to redirect_to(preview_indexer_apps_path(assignment_ids: [ assignment.id ]))
    expect(flash[:alert]).to include("Confirm", "disable remote search modes")
    expect(SyncRun.count).to eq(0)
  end

  it "returns an empty apply submission to the matrix instead of expanding its scope" do
    assignment
    allow(Sync::Plan).to receive(:call).and_call_original

    post apply_plan_indexer_apps_path

    expect(response).to redirect_to(indexer_apps_path)
    expect(flash[:alert]).to include("No selected reconciliation changes")
    expect(SyncRun.count).to eq(0)
  end

  it "refuses to repair an association when the remote conflict changed" do
    conflict = Sync::Plan::Item.new(
      indexer_app: assignment,
      state: "conflict",
      remote_indexer_id: 42,
      changes: [],
      message: "Conflict.",
      desired_digest: "desired",
      remote_digest: "remote",
      plan_digest: "conflict-plan",
      destructive: false
    )
    allow(Sync::Plan).to receive(:call).and_return(Sync::Plan::Result.new(items: [ conflict ], generated_at: Time.current))

    post repair_indexer_app_path(assignment), params: { remote_indexer_id: 99 }

    expect(response).to redirect_to(preview_indexer_apps_path(assignment_ids: [ assignment.id ]))
    expect(flash[:alert]).to include("conflict changed")
    expect(assignment.reload.remote_indexer_id).to be_nil
  end

  it "returns a repaired assignment with disabled search modes to preview instead of syncing it" do
    assignment.update!(enable_rss: false)
    conflict = Sync::Plan::Item.new(
      indexer_app: assignment,
      state: "conflict",
      remote_indexer_id: 42,
      changes: [],
      message: "Conflict.",
      desired_digest: "desired",
      remote_digest: "remote",
      plan_digest: "conflict-plan",
      destructive: false
    )
    allow(Sync::Plan).to receive(:call).and_return(Sync::Plan::Result.new(items: [ conflict ], generated_at: Time.current))
    allow(Sync::AssignmentSync).to receive(:call)

    post repair_indexer_app_path(assignment), params: { remote_indexer_id: 42 }

    expect(response).to redirect_to(preview_indexer_apps_path(assignment_ids: [ assignment.id ]))
    expect(flash[:notice]).to include("Review and confirm the search-mode desired state")
    expect(assignment.reload.remote_indexer_id).to eq(42)
    expect(Sync::AssignmentSync).not_to have_received(:call)
  end

  it "does not forget a remote association while its sync is active" do
    assignment.update!(remote_indexer_id: 42)
    sync_run = SyncRun.create!(status: "running", total_count: 1)
    sync_run.sync_run_items.create!(indexer_app: assignment, status: "running")

    post forget_remote_indexer_app_path(assignment)

    expect(response).to redirect_to(preview_indexer_apps_path(assignment_ids: [ assignment.id ]))
    expect(flash[:alert]).to include("active assignment sync")
    expect(assignment.reload.remote_indexer_id).to eq(42)
  end

  it "rechecks active sync state immediately before repairing an association" do
    conflict = Sync::Plan::Item.new(
      indexer_app: assignment,
      state: "conflict",
      remote_indexer_id: 42,
      changes: [],
      message: "Conflict.",
      desired_digest: "desired",
      remote_digest: "remote",
      plan_digest: "conflict-plan",
      destructive: false
    )
    allow(Sync::Plan).to receive(:call) do
      sync_run = SyncRun.create!(status: "running", total_count: 1)
      sync_run.sync_run_items.create!(indexer_app: assignment, status: "running")
      Sync::Plan::Result.new(items: [ conflict ], generated_at: Time.current)
    end

    post repair_indexer_app_path(assignment), params: { remote_indexer_id: 42 }

    expect(response).to redirect_to(preview_indexer_apps_path(assignment_ids: [ assignment.id ]))
    expect(flash[:alert]).to include("active assignment sync")
    expect(assignment.reload.remote_indexer_id).to be_nil
  end
end
