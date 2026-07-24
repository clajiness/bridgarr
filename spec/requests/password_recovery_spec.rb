require "rails_helper"

RSpec.describe "Password recovery", type: :request, skip_authentication: true do
  let!(:user) do
    User.create!(
      email: "admin@example.com",
      password: "correct-horse-battery-staple",
      password_confirmation: "correct-horse-battery-staple",
      local_admin_slot: User::LOCAL_ADMIN_SLOT
    )
  end

  before do
    ActionMailer::Base.deliveries.clear
  end

  it "sends reset instructions to the administrator" do
    post user_password_path, params: { user: { email: user.email } }

    expect(response).to redirect_to(new_user_session_path)
    expect(ActionMailer::Base.deliveries.size).to eq(1)
    expect(ActionMailer::Base.deliveries.last.to).to contain_exactly(user.email)
  end

  it "does not reveal whether an email address exists" do
    post user_password_path, params: { user: { email: "unknown@example.com" } }

    expect(response).to redirect_to(new_user_session_path)
    expect(flash[:notice]).to eq(I18n.t("devise.passwords.send_paranoid_instructions"))
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "returns the same paranoid response when delivery succeeds, the account is missing, or delivery fails" do
    successful_existing_response = request_recovery(user.email)
    missing_response = request_recovery("missing@example.com")

    log_output = StringIO.new
    recovery_logger = ActiveSupport::TaggedLogging.new(
      ActiveSupport::Logger.new(log_output, level: Logger::ERROR)
    )
    Rails.logger.broadcast_to(recovery_logger)
    allow_any_instance_of(User)
      .to receive(:send_devise_notification)
      .and_wrap_original do
        ActionMailer::Base.logger.error(
          "delivery failed for admin@example.com with reset_password_token=secret-reset-token"
        )
        raise IOError, "SMTP delivery failed"
      end

    failed_existing_response = request_recovery(user.email)
    failed_missing_response = request_recovery("another-missing@example.com")
    recovery_logger.flush

    expect(
      [
        successful_existing_response,
        missing_response,
        failed_existing_response,
        failed_missing_response
      ].uniq
    ).to contain_exactly(successful_existing_response)
    expect(log_output.string).to include("Password recovery email delivery failed.")
    expect(log_output.string).not_to include(
      "admin@example.com",
      "secret-reset-token"
    )
  ensure
    Rails.logger.stop_broadcasting_to(recovery_logger) if recovery_logger
  end

  it "does not swallow errors outside the recovery notification operation" do
    allow(User)
      .to receive(:send_reset_password_instructions)
      .and_raise(NoMethodError, "unrelated programming error")

    expect do
      post user_password_path, params: { user: { email: user.email } }
    end.to raise_error(NoMethodError, "unrelated programming error")
  end

  it "updates the password without automatically signing in" do
    raw_token = user.send_reset_password_instructions

    put user_password_path, params: {
      user: {
        reset_password_token: raw_token,
        password: "new-correct-horse-battery-staple",
        password_confirmation: "new-correct-horse-battery-staple"
      }
    }

    expect(response).to redirect_to(new_user_session_path)
    expect(user.reload.valid_password?("new-correct-horse-battery-staple")).to be(true)
    get root_path
    expect(response).to redirect_to(new_user_session_path)
  end

  def request_recovery(email)
    post user_password_path, params: { user: { email: } }

    {
      status: response.status,
      location: response.location,
      flash: flash.to_hash,
      body: response.body
    }
  end
end
