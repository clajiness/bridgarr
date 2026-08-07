require "io/console"

namespace :bridgarr do
  desc "Repair pre-v0.6 assignments whose enabled state was never stored"
  task repair_legacy_assignment_state: :environment do
    migration_indexer_app = Class.new(ActiveRecord::Base) do
      self.table_name = "indexer_apps"
    end
    legacy_assignments = migration_indexer_app.unscoped.where(enabled: nil)
    count = legacy_assignments.count
    dry_run = ActiveModel::Type::Boolean.new.cast(ENV["DRY_RUN"])
    confirmed = ENV["CONFIRM"] == "true"

    puts "Found #{count} pre-v0.6 #{'assignment'.pluralize(count)} with an unset desired state."

    if count.zero?
      puts "No local assignment state needs repair."
    elsif dry_run
      puts "Dry run only; no assignments were changed."
    elsif !confirmed
      puts "No assignments were changed. Re-run with CONFIRM=true to repair local desired state."
    else
      updated_count = legacy_assignments.update_all(enabled: true)
      puts "Repaired #{updated_count} local #{'assignment'.pluralize(updated_count)}; no remote sync was started."
    end

    puts "Use Preview changes and review the plan before syncing any assignment."
  end

  namespace :admin do
    desc "Create the single local Bridgarr administrator account"
    task create: :environment do
      abort "A local administrator already exists." if User.local_administrator.exists?

      email = ENV["BRIDGARR_ADMIN_EMAIL"].presence
      unless email
        $stdout.print("Administrator email: ")
        $stdout.flush
        email = $stdin.gets.to_s.strip
      end

      password = ENV["BRIDGARR_ADMIN_PASSWORD"].presence || $stdin.getpass("Administrator password: ")
      confirmation = ENV["BRIDGARR_ADMIN_PASSWORD"].present? ? password : $stdin.getpass("Confirm password: ")

      user = User.create!(
        email:,
        password:,
        password_confirmation: confirmation,
        local_admin_slot: User::LOCAL_ADMIN_SLOT
      )

      puts "Local administrator created for #{user.email}."
    rescue ActiveRecord::RecordNotUnique
      abort "A local administrator was created concurrently. No additional administrator was added."
    rescue ActiveRecord::RecordInvalid => error
      if error.record.errors.of_kind?(:local_admin_slot, :taken)
        abort "A local administrator was created concurrently. No additional administrator was added."
      end

      abort error.record.errors.full_messages.to_sentence
    end

    desc "Reset and unlock the Bridgarr administrator account"
    task reset_password: :environment do
      user = User.local_administrator.first
      abort "No local administrator exists. Run bridgarr:admin:create first." unless user

      password = ENV["BRIDGARR_ADMIN_PASSWORD"].presence || $stdin.getpass("New administrator password: ")
      confirmation = ENV["BRIDGARR_ADMIN_PASSWORD"].present? ? password : $stdin.getpass("Confirm password: ")

      user.with_lock do
        user.password = password
        user.password_confirmation = confirmation
        user.locked_at = nil
        user.failed_attempts = 0
        user.save!
      end

      puts "Administrator password reset for #{user.email}."
    rescue ActiveRecord::RecordInvalid => error
      abort error.record.errors.full_messages.to_sentence
    end
  end
end
