# frozen_string_literal: true

class DeviseCreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      ## Database authenticatable
      t.string :email,              null: false, default: ""
      t.string :encrypted_password, null: false, default: ""

      ## Recoverable
      t.string   :reset_password_token
      t.datetime :reset_password_sent_at

      ## Lockable
      t.integer  :failed_attempts, default: 0, null: false
      t.datetime :locked_at

      # Nullable so a later OIDC phase can add non-local users. The fixed value
      # and unique index reserve exactly one database-enforced local-admin slot.
      t.integer :local_admin_slot

      t.timestamps null: false
    end

    add_index :users, :email,                unique: true
    add_index :users, :reset_password_token, unique: true
    add_index :users, :local_admin_slot,      unique: true
    add_check_constraint :users,
      "local_admin_slot IS NULL OR local_admin_slot = 1",
      name: "users_local_admin_slot_is_one"
  end
end
