# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_07_07_170000) do
  create_table "arr_apps", force: :cascade do |t|
    t.string "api_key"
    t.string "app_type"
    t.string "base_url"
    t.datetime "created_at", null: false
    t.boolean "enabled"
    t.text "last_error"
    t.string "last_status"
    t.datetime "last_tested_at"
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "indexer_apps", force: :cascade do |t|
    t.integer "arr_app_id", null: false
    t.string "category_mode", default: "auto", null: false
    t.string "connection_mode", default: "direct", null: false
    t.datetime "created_at", null: false
    t.text "custom_categories"
    t.boolean "enabled"
    t.integer "indexer_id", null: false
    t.text "last_error"
    t.string "last_status"
    t.datetime "last_synced_at"
    t.integer "remote_indexer_id"
    t.datetime "updated_at", null: false
    t.index ["arr_app_id"], name: "index_indexer_apps_on_arr_app_id"
    t.index ["indexer_id"], name: "index_indexer_apps_on_indexer_id"
  end

  create_table "indexers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "enabled"
    t.string "jackett_id"
    t.text "last_error"
    t.string "last_status"
    t.datetime "last_tested_at"
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "proxy_requests", force: :cascade do |t|
    t.string "categories"
    t.datetime "created_at", null: false
    t.integer "duration_ms", default: 0, null: false
    t.text "error"
    t.integer "http_status"
    t.integer "indexer_id"
    t.integer "item_count"
    t.string "jackett_id", null: false
    t.string "query"
    t.text "query_params"
    t.string "request_type", null: false
    t.datetime "updated_at", null: false
    t.index ["indexer_id", "created_at"], name: "index_proxy_requests_on_indexer_id_and_created_at"
    t.index ["indexer_id"], name: "index_proxy_requests_on_indexer_id"
    t.index ["jackett_id", "created_at"], name: "index_proxy_requests_on_jackett_id_and_created_at"
    t.index ["request_type"], name: "index_proxy_requests_on_request_type"
  end

  create_table "settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key"
    t.datetime "updated_at", null: false
    t.text "value"
  end

  create_table "sync_run_items", force: :cascade do |t|
    t.string "arr_app_name"
    t.integer "attempt_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.text "error"
    t.string "error_kind"
    t.datetime "finished_at"
    t.integer "indexer_app_id"
    t.string "indexer_name"
    t.datetime "last_attempt_at"
    t.integer "max_attempts", default: 2, null: false
    t.datetime "next_retry_at"
    t.boolean "retryable", default: false, null: false
    t.datetime "started_at"
    t.string "status", default: "queued", null: false
    t.integer "sync_run_id", null: false
    t.datetime "updated_at", null: false
    t.index ["indexer_app_id", "created_at"], name: "index_sync_run_items_on_indexer_app_id_and_created_at"
    t.index ["indexer_app_id"], name: "index_sync_run_items_on_indexer_app_id"
    t.index ["status", "next_retry_at"], name: "index_sync_run_items_on_status_and_next_retry_at"
    t.index ["sync_run_id", "status"], name: "index_sync_run_items_on_sync_run_id_and_status"
    t.index ["sync_run_id"], name: "index_sync_run_items_on_sync_run_id"
  end

  create_table "sync_runs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.integer "failure_count", default: 0, null: false
    t.datetime "finished_at"
    t.string "mode", default: "bulk", null: false
    t.integer "skipped_count", default: 0, null: false
    t.datetime "started_at"
    t.string "status", default: "queued", null: false
    t.integer "success_count", default: 0, null: false
    t.integer "total_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["mode"], name: "index_sync_runs_on_mode"
    t.index ["status", "created_at"], name: "index_sync_runs_on_status_and_created_at"
  end

  add_foreign_key "indexer_apps", "arr_apps"
  add_foreign_key "indexer_apps", "indexers"
  add_foreign_key "proxy_requests", "indexers"
  add_foreign_key "sync_run_items", "indexer_apps", on_delete: :nullify
  add_foreign_key "sync_run_items", "sync_runs"
end
