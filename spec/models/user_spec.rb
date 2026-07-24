require "rails_helper"

RSpec.describe User, type: :model do
  subject(:user) do
    described_class.new(
      email: "admin@example.com",
      password: "correct-horse-battery-staple",
      password_confirmation: "correct-horse-battery-staple",
      local_admin_slot: described_class::LOCAL_ADMIN_SLOT
    )
  end

  it "uses the configured Devise modules without public registration" do
    expect(described_class.devise_modules).to include(
      :database_authenticatable,
      :recoverable,
      :validatable,
      :timeoutable,
      :lockable
    )
    expect(described_class.devise_modules).not_to include(:registerable, :omniauthable)
  end

  it "requires a sufficiently long password" do
    user.password = "too-short"
    user.password_confirmation = "too-short"

    expect(user).not_to be_valid
    expect(user.errors[:password]).to be_present
  end

  it "locks after the configured number of failed attempts" do
    user.save!

    Devise.maximum_attempts.times { user.increment_failed_attempts }
    user.lock_access!

    expect(user).to be_access_locked
  end

  it "recognizes an inactive session timeout" do
    expect(user).to be_timedout(Devise.timeout_in.ago - 1.second)
    expect(user).not_to be_timedout(Time.current)
  end

  it "allows future non-local users to leave the local administrator slot empty" do
    user.local_admin_slot = nil

    expect(user).to be_valid
  end

  it "rejects local administrator slot values other than one" do
    user.local_admin_slot = 2

    expect(user).not_to be_valid
    expect(user.errors[:local_admin_slot]).to be_present
  end

  it "enforces the single local administrator slot in the database" do
    user.save!
    now = Time.current

    expect do
      described_class.insert_all!([
        {
          email: "second@example.com",
          encrypted_password: user.encrypted_password,
          failed_attempts: 0,
          local_admin_slot: described_class::LOCAL_ADMIN_SLOT,
          created_at: now,
          updated_at: now
        }
      ])
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "enforces the fixed local administrator slot value in the database" do
    now = Time.current

    expect do
      described_class.insert_all!([
        {
          email: "invalid-slot@example.com",
          encrypted_password: user.encrypted_password,
          failed_attempts: 0,
          local_admin_slot: 2,
          created_at: now,
          updated_at: now
        }
      ])
    end.to raise_error(ActiveRecord::StatementInvalid)
  end
end
