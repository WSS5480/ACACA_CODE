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

ActiveRecord::Schema[7.1].define(version: 2026_07_10_000003) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "app_settings", force: :cascade do |t|
    t.string "key", null: false
    t.text "value"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_app_settings_on_key", unique: true
  end

  create_table "beneficiaries", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name"
    t.string "last_name"
    t.string "email"
    t.string "phone"
    t.string "address1"
    t.string "address2"
    t.string "zip_code"
    t.string "state"
    t.string "city"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_beneficiaries_on_user_id"
  end

  create_table "buyers", force: :cascade do |t|
    t.bigint "order_id", null: false
    t.string "name"
    t.string "last_name"
    t.string "nationality"
    t.string "state_residence"
    t.string "living_address1"
    t.string "living_address2"
    t.string "living_zip_code"
    t.string "living_state"
    t.string "living_city"
    t.string "housing_type"
    t.string "months_usa"
    t.string "months_address"
    t.string "job"
    t.string "phone"
    t.string "phone_work"
    t.string "email"
    t.decimal "weekly_income", precision: 10, scale: 2
    t.string "relationship_with_beneficiary"
    t.string "delivery_address1"
    t.string "delivery_address2"
    t.string "delivery_zip_code"
    t.string "delivery_state"
    t.string "delivery_city"
    t.string "phone_beneficiary"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_buyers_on_order_id"
  end

  create_table "categories", force: :cascade do |t|
    t.string "name"
    t.string "external_id"
    t.string "original_link"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "credits", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.decimal "amount", precision: 10, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_credits_on_user_id"
  end

  create_table "exchange_rates", force: :cascade do |t|
    t.decimal "usd_to_mxn", precision: 10, scale: 2
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "guarantors", force: :cascade do |t|
    t.bigint "order_id", null: false
    t.string "name"
    t.string "last_name"
    t.string "address1"
    t.string "address2"
    t.string "zip_code"
    t.string "state"
    t.string "city"
    t.string "phone"
    t.string "email"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_guarantors_on_order_id"
  end

  create_table "orders", force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "product_id"
    t.string "user_name"
    t.string "user_last_name"
    t.string "user_email"
    t.string "product_title"
    t.string "product_asin"
    t.decimal "product_price", precision: 10, scale: 2
    t.decimal "product_original_price", precision: 10, scale: 2
    t.decimal "product_turns", precision: 10, scale: 2
    t.decimal "product_decimal_factor", precision: 10, scale: 2
    t.decimal "used_credit", precision: 10, scale: 2
    t.decimal "downpayment", precision: 10, scale: 2
    t.decimal "weekly_payment", precision: 10, scale: 2
    t.integer "credit_duration"
    t.string "status", default: "pending"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "hightouch_id"
    t.bigint "beneficiary_id"
    t.decimal "product_price_with_discount", precision: 10, scale: 2
    t.decimal "waiver", precision: 10, scale: 2, default: "0.0"
    t.index ["beneficiary_id"], name: "index_orders_on_beneficiary_id"
    t.index ["hightouch_id"], name: "index_orders_on_hightouch_id"
    t.index ["product_id"], name: "index_orders_on_product_id"
    t.index ["user_id"], name: "index_orders_on_user_id"
  end

  create_table "product_categories", force: :cascade do |t|
    t.bigint "product_id", null: false
    t.bigint "category_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_product_categories_on_category_id"
    t.index ["product_id"], name: "index_product_categories_on_product_id"
  end

  create_table "products", force: :cascade do |t|
    t.string "title"
    t.string "keywords"
    t.string "asin"
    t.text "original_link"
    t.string "brand"
    t.float "rating"
    t.text "feature_bullets"
    t.decimal "price", precision: 10, scale: 2
    t.string "currency"
    t.string "color"
    t.string "material"
    t.string "dimensions"
    t.string "model_number"
    t.string "external_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "original_price", precision: 10, scale: 2
    t.decimal "min_weekly_payment", precision: 10, scale: 2
    t.decimal "turns", precision: 10, scale: 2, default: "3.5"
    t.decimal "decimal_factor", precision: 10, scale: 2, default: "0.75"
    t.string "status", default: "active"
    t.decimal "price_with_discount", precision: 10, scale: 2
    t.index ["asin"], name: "index_products_on_asin", unique: true
    t.index ["external_id"], name: "index_products_on_external_id"
  end

  create_table "referrals", force: :cascade do |t|
    t.bigint "order_id", null: false
    t.string "nationality"
    t.string "name"
    t.string "last_name"
    t.string "phone"
    t.string "phone_work"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_referrals_on_order_id"
  end

  create_table "risk_engine_configs", force: :cascade do |t|
    t.integer "version", null: false
    t.text "notes"
    t.jsonb "config", default: {}, null: false
    t.boolean "active", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_risk_engine_configs_on_active"
    t.index ["version"], name: "index_risk_engine_configs_on_version", unique: true
  end

  create_table "roles", force: :cascade do |t|
    t.string "name"
    t.string "label"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "specifications_lists", force: :cascade do |t|
    t.bigint "product_id", null: false
    t.text "bullets"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id"], name: "index_specifications_lists_on_product_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "name"
    t.string "last_name"
    t.string "number"
    t.string "phone"
    t.string "housing_type"
    t.string "months_usa"
    t.string "months_address"
    t.string "months_job"
    t.string "estimated_income"
    t.string "delivery_country"
    t.string "shared_income"
    t.string "jti", null: false
    t.bigint "role_id", null: false
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "confirmation_sent_at"
    t.integer "risk_version"
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["jti"], name: "index_users_on_jti", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["role_id"], name: "index_users_on_role_id"
  end

  create_table "zip_codes", force: :cascade do |t|
    t.string "code"
    t.string "country"
    t.string "state_initials"
    t.string "state_name"
    t.string "city"
    t.string "municipality"
    t.string "settlement"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["city"], name: "index_zip_codes_on_city"
    t.index ["code"], name: "index_zip_codes_on_code"
    t.index ["country"], name: "index_zip_codes_on_country"
    t.index ["state_initials"], name: "index_zip_codes_on_state_initials"
    t.index ["state_name"], name: "index_zip_codes_on_state_name"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "beneficiaries", "users"
  add_foreign_key "buyers", "orders"
  add_foreign_key "credits", "users"
  add_foreign_key "guarantors", "orders"
  add_foreign_key "orders", "beneficiaries"
  add_foreign_key "orders", "products"
  add_foreign_key "orders", "users"
  add_foreign_key "product_categories", "categories"
  add_foreign_key "product_categories", "products"
  add_foreign_key "referrals", "orders"
  add_foreign_key "specifications_lists", "products"
  add_foreign_key "users", "roles"
end
