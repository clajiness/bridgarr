require Rails.root.join("lib/bridgarr/sensitive_log_silencer")

class User < ApplicationRecord
  LOCAL_ADMIN_SLOT = 1

  devise :database_authenticatable,
    :recoverable,
    :validatable,
    :timeoutable,
    :lockable

  scope :local_administrator, -> { where(local_admin_slot: LOCAL_ADMIN_SLOT) }

  validates :local_admin_slot,
    inclusion: { in: [ LOCAL_ADMIN_SLOT ] },
    uniqueness: true,
    allow_nil: true

  protected

    # Keep Devise's paranoid recovery response intact when the delivery
    # operation fails. Errors outside the notification boundary still surface.
    def send_reset_password_instructions_notification(token)
      Bridgarr::SensitiveLogSilencer.call(ActionMailer::Base.logger) { super }
    rescue StandardError
      Rails.logger.error("Password recovery email delivery failed.")
    end
end
