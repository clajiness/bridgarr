class ApplicationController < ActionController::Base
  before_action :redirect_to_admin_setup, unless: :local_administrator_configured?
  before_action :authenticate_user!, unless: :devise_controller?

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private

    def local_administrator_configured?
      User.local_administrator.exists?
    end

    def redirect_to_admin_setup
      redirect_to new_admin_setup_path
    end

    def after_sign_out_path_for(_resource_or_scope)
      new_user_session_path
    end
end
