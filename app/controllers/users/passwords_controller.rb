module Users
  class PasswordsController < Devise::PasswordsController
    include AuthenticationRateLimited

    private

      def authentication_rate_limit_exceeded
        redirect_to new_user_password_path,
          alert: "Too many authentication attempts. Try again later.",
          status: :see_other
      end
  end
end
