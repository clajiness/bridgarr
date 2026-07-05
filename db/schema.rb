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

ActiveRecord::Schema[8.1].define(version: 2026_07_04_231804) do
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
    t.datetime "created_at", null: false
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

  add_foreign_key "indexer_apps", "arr_apps"
  add_foreign_key "indexer_apps", "indexers"
  add_foreign_key "proxy_requests", "indexers"
end
