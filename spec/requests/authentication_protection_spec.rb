require "rails_helper"

RSpec.describe "Authentication protection", type: :request, skip_authentication: true do
  APPLICATION_CONTROLLERS = %w[
    arr_apps
    dashboard
    indexer_apps
    indexers
    jobs
    proxy_activities
    settings
    sync_runs
  ].freeze

  PROTECTED_ROUTES = Rails.application.routes.routes.filter_map do |route|
    controller = route.requirements[:controller]
    next unless APPLICATION_CONTROLLERS.include?(controller)

    route.verb.split("|").map do |verb|
      {
        verb: verb.downcase,
        path: route.path.spec.to_s.delete_suffix("(.:format)").gsub(":id", "1"),
        controller: "#{controller.camelize}Controller".constantize,
        action: route.requirements.fetch(:action)
      }
    end
  end.flatten.freeze

  PROTECTED_ROUTES.each do |protected_route|
    signature = "#{protected_route.fetch(:verb).upcase} #{protected_route.fetch(:path)}"

    it "sends #{signature} to first-run setup when no administrator exists" do
      allow_any_instance_of(protected_route.fetch(:controller))
        .to receive(protected_route.fetch(:action))
        .and_raise("protected action was reached")

      public_send(protected_route.fetch(:verb), protected_route.fetch(:path))

      expect(response).to redirect_to(new_admin_setup_path)
    end

    it "requires a session for #{signature} after setup" do
      User.create!(
        email: "admin@example.com",
        password: "correct-horse-battery-staple",
        password_confirmation: "correct-horse-battery-staple",
        local_admin_slot: User::LOCAL_ADMIN_SLOT
      )
      allow_any_instance_of(protected_route.fetch(:controller))
        .to receive(protected_route.fetch(:action))
        .and_raise("protected action was reached")

      public_send(protected_route.fetch(:verb), protected_route.fetch(:path))

      expect(response).to redirect_to(new_user_session_path)
    end

    it "allows an authenticated administrator to reach #{signature}" do
      user = User.create!(
        email: "admin@example.com",
        password: "correct-horse-battery-staple",
        password_confirmation: "correct-horse-battery-staple",
        local_admin_slot: User::LOCAL_ADMIN_SLOT
      )
      sign_in(user)
      allow_any_instance_of(protected_route.fetch(:controller))
        .to receive(protected_route.fetch(:action)) do |controller|
          controller.head(:no_content)
        end

      public_send(protected_route.fetch(:verb), protected_route.fetch(:path))

      expect(response).not_to redirect_to(new_admin_setup_path)
      expect(response).not_to redirect_to(new_user_session_path)
    end
  end

  it "returns unauthorized instead of redirecting for unauthenticated JSON requests" do
    User.create!(
      email: "admin@example.com",
      password: "correct-horse-battery-staple",
      password_confirmation: "correct-horse-battery-staple",
      local_admin_slot: User::LOCAL_ADMIN_SLOT
    )

    get arr_apps_path(format: :json)

    expect(response).to have_http_status(:unauthorized)
  end

  it "leaves the Rails liveness endpoint public" do
    get rails_health_check_path

    expect(response).to have_http_status(:ok)
  end
end
