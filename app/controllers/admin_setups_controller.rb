class AdminSetupsController < ApplicationController
  skip_before_action :redirect_to_admin_setup
  skip_before_action :authenticate_user!

  before_action :redirect_if_configured

  def new
  end

  private

    def redirect_if_configured
      return unless User.local_administrator.exists?

      redirect_to(user_signed_in? ? root_path : new_user_session_path)
    end
end
