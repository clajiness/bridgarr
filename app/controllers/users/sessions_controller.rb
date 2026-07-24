module Users
  class SessionsController < Devise::SessionsController
    include AuthenticationRateLimited

    private

      def authentication_rate_limit_exceeded
        redirect_to new_user_session_path,
          alert: "Too many authentication attempts. Try again later.",
          status: :see_other
      end
  end
end
