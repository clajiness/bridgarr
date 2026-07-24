require "rails_helper"
require "rake"
require "stringio"

RSpec.describe "Bridgarr administrator tasks" do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("bridgarr:admin:create")
  end

  around do |example|
    original_email = ENV["BRIDGARR_ADMIN_EMAIL"]
    original_password = ENV["BRIDGARR_ADMIN_PASSWORD"]
    example.run
  ensure
    original_email.nil? ? ENV.delete("BRIDGARR_ADMIN_EMAIL") : ENV["BRIDGARR_ADMIN_EMAIL"] = original_email
    original_password.nil? ? ENV.delete("BRIDGARR_ADMIN_PASSWORD") : ENV["BRIDGARR_ADMIN_PASSWORD"] = original_password
  end

  it "creates the single local administrator noninteractively for deployment automation" do
    ENV["BRIDGARR_ADMIN_EMAIL"] = "admin@example.com"
    ENV["BRIDGARR_ADMIN_PASSWORD"] = "correct-horse-battery-staple"
    task = Rake::Task["bridgarr:admin:create"]
    task.reenable

    expect do
      task.invoke
    end.to change(User.local_administrator, :count).by(1)

    expect(User.local_administrator.first).to have_attributes(
      email: "admin@example.com",
      local_admin_slot: User::LOCAL_ADMIN_SLOT
    )
  end

  it "reports a concurrent local administrator creation conflict cleanly" do
    ENV["BRIDGARR_ADMIN_EMAIL"] = "admin@example.com"
    ENV["BRIDGARR_ADMIN_PASSWORD"] = "correct-horse-battery-staple"
    allow(User).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique, "duplicate local admin slot")
    task = Rake::Task["bridgarr:admin:create"]
    task.reenable

    error_output = capture_stderr do
      expect { task.invoke }.to raise_error(SystemExit)
    end

    expect(error_output).to include("created concurrently")
    expect(User.local_administrator).to be_empty
  end

  it "leaves a locked account unchanged when the replacement password is invalid" do
    user = create_local_administrator
    user.update!(failed_attempts: Devise.maximum_attempts, locked_at: Time.current)
    original_encrypted_password = user.encrypted_password
    original_locked_at = user.locked_at
    ENV["BRIDGARR_ADMIN_PASSWORD"] = "short"
    task = Rake::Task["bridgarr:admin:reset_password"]
    task.reenable

    error_output = capture_stderr do
      expect { task.invoke }.to raise_error(SystemExit)
    end

    user.reload
    expect(error_output).to include("Password is too short")
    expect(user.encrypted_password).to eq(original_encrypted_password)
    expect(user.locked_at).to eq(original_locked_at)
    expect(user.failed_attempts).to eq(Devise.maximum_attempts)
    expect(user).to be_access_locked
    expect(user).not_to be_valid_password("short")
  end

  it "resets the password and lock state in one successful transaction" do
    user = create_local_administrator
    user.update!(failed_attempts: Devise.maximum_attempts, locked_at: Time.current)
    ENV["BRIDGARR_ADMIN_PASSWORD"] = "replacement-password-123"
    task = Rake::Task["bridgarr:admin:reset_password"]
    task.reenable

    task.invoke

    user.reload
    expect(user).to be_valid_password("replacement-password-123")
    expect(user).not_to be_access_locked
    expect(user.failed_attempts).to eq(0)
    expect(user.locked_at).to be_nil
  end

  private

    def create_local_administrator
      User.create!(
        email: "admin@example.com",
        password: "correct-horse-battery-staple",
        password_confirmation: "correct-horse-battery-staple",
        local_admin_slot: User::LOCAL_ADMIN_SLOT
      )
    end

    def capture_stderr
      original_stderr = $stderr
      captured_stderr = StringIO.new
      $stderr = captured_stderr
      yield
      captured_stderr.string
    ensure
      $stderr = original_stderr
    end
end
