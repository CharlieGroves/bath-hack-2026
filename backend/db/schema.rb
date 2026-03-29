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

ActiveRecord::Schema[7.2].define(version: 2026_03_29_000000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "air_quality_stations", force: :cascade do |t|
    t.integer "external_id", null: false
    t.string "name", null: false
    t.decimal "latitude", precision: 10, scale: 7, null: false
    t.decimal "longitude", precision: 10, scale: 7, null: false
    t.integer "daqi_index"
    t.string "daqi_band"
    t.datetime "readings_fetched_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["daqi_index"], name: "index_air_quality_stations_on_daqi_index"
    t.index ["external_id"], name: "index_air_quality_stations_on_external_id", unique: true
    t.index ["latitude", "longitude"], name: "index_air_quality_stations_on_latitude_and_longitude"
  end

  create_table "area_price_growths", force: :cascade do |t|
    t.string "area_slug", null: false
    t.string "area_name", null: false
    t.jsonb "yearly_growth_data", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["area_slug"], name: "index_area_price_growths_on_area_slug", unique: true
  end

  create_table "boroughs", force: :cascade do |t|
    t.string "name", null: false
    t.float "nte_score_raw"
    t.float "nte_score", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.float "life_satisfaction_score_raw"
    t.float "life_satisfaction_score"
    t.float "happiness_score_raw"
    t.float "happiness_score"
    t.float "anxiety_score_raw"
    t.float "anxiety_score"
    t.index ["name"], name: "index_boroughs_on_name", unique: true
  end

  create_table "estate_agents", force: :cascade do |t|
    t.string "lookup_key", null: false
    t.string "google_place_id", null: false
    t.string "display_name"
    t.decimal "rating", precision: 2, scale: 1
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["google_place_id"], name: "index_estate_agents_on_google_place_id", unique: true
    t.index ["lookup_key"], name: "index_estate_agents_on_lookup_key", unique: true
  end

  create_table "flood_risk_datapoints", force: :cascade do |t|
    t.decimal "latitude", precision: 10, scale: 7, null: false
    t.decimal "longitude", precision: 10, scale: 7, null: false
    t.string "risk_level", null: false
    t.integer "risk_band", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["latitude", "longitude"], name: "index_flood_risk_datapoints_on_latitude_and_longitude"
    t.index ["risk_band"], name: "index_flood_risk_datapoints_on_risk_band"
  end

  create_table "properties", force: :cascade do |t|
    t.string "rightmove_id", null: false
    t.string "slug", null: false
    t.string "listing_url"
    t.string "title"
    t.text "description"
    t.jsonb "key_features", default: [], null: false
    t.jsonb "photo_urls", default: [], null: false
    t.bigint "price_pence"
    t.string "price_qualifier"
    t.bigint "price_per_sqft_pence"
    t.string "property_type"
    t.integer "bedrooms"
    t.integer "bathrooms"
    t.integer "size_sqft"
    t.string "tenure"
    t.integer "lease_years_remaining"
    t.string "epc_rating"
    t.string "council_tax_band"
    t.bigint "service_charge_annual_pence"
    t.string "address_line_1"
    t.string "town"
    t.string "postcode"
    t.decimal "latitude", precision: 10, scale: 7
    t.decimal "longitude", precision: 10, scale: 7
    t.string "agent_name"
    t.string "agent_phone"
    t.boolean "has_floor_plan", default: false, null: false
    t.boolean "has_virtual_tour", default: false, null: false
    t.string "utilities_text"
    t.string "parking_text"
    t.string "status", default: "active", null: false
    t.datetime "listed_at"
    t.datetime "last_seen_at"
    t.jsonb "raw_data"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "air_quality_station_id"
    t.bigint "area_price_growth_id"
    t.bigint "flood_risk_datapoint_id"
    t.bigint "estate_agent_id"
    t.bigint "borough_id"
    t.index ["air_quality_station_id"], name: "index_properties_on_air_quality_station_id"
    t.index ["area_price_growth_id"], name: "index_properties_on_area_price_growth_id"
    t.index ["bedrooms"], name: "index_properties_on_bedrooms"
    t.index ["borough_id"], name: "index_properties_on_borough_id"
    t.index ["estate_agent_id"], name: "index_properties_on_estate_agent_id"
    t.index ["flood_risk_datapoint_id"], name: "index_properties_on_flood_risk_datapoint_id"
    t.index ["latitude", "longitude", "price_per_sqft_pence"], name: "idx_on_latitude_longitude_price_per_sqft_pence_636bf349eb", where: "((latitude IS NOT NULL) AND (longitude IS NOT NULL) AND (price_per_sqft_pence IS NOT NULL))"
    t.index ["latitude", "longitude"], name: "index_properties_on_latitude_and_longitude"
    t.index ["listed_at"], name: "index_properties_on_listed_at"
    t.index ["postcode"], name: "index_properties_on_postcode"
    t.index ["price_pence"], name: "index_properties_on_price_pence"
    t.index ["property_type"], name: "index_properties_on_property_type"
    t.index ["rightmove_id"], name: "index_properties_on_rightmove_id", unique: true
    t.index ["slug"], name: "index_properties_on_slug", unique: true
    t.index ["status", "property_type", "price_pence"], name: "index_properties_on_status_and_property_type_and_price_pence"
    t.index ["status"], name: "index_properties_on_status"
    t.index ["tenure"], name: "index_properties_on_tenure"
  end

  create_table "property_crime_snapshots", force: :cascade do |t|
    t.bigint "property_id", null: false
    t.decimal "latitude", precision: 10, scale: 7
    t.decimal "longitude", precision: 10, scale: 7
    t.float "avg_monthly_crimes"
    t.string "status", default: "pending", null: false
    t.datetime "fetched_at"
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["property_id"], name: "index_property_crime_snapshots_on_property_id", unique: true
    t.index ["status", "fetched_at"], name: "index_property_crime_snapshots_on_status_and_fetched_at"
  end

  create_table "property_images", force: :cascade do |t|
    t.bigint "property_id", null: false
    t.string "url", null: false
    t.integer "position", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["property_id"], name: "index_property_images_on_property_id"
  end

  create_table "property_nearest_stations", force: :cascade do |t|
    t.bigint "property_id", null: false
    t.string "name", null: false
    t.decimal "distance_miles", precision: 5, scale: 2
    t.string "transport_type"
    t.integer "walking_minutes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "termini", default: [], array: true
    t.index ["distance_miles"], name: "index_property_nearest_stations_on_distance_miles"
    t.index ["property_id"], name: "index_property_nearest_stations_on_property_id"
    t.index ["walking_minutes"], name: "index_property_nearest_stations_on_walking_minutes"
  end

  create_table "property_transport_snapshots", force: :cascade do |t|
    t.bigint "property_id", null: false
    t.string "provider", null: false
    t.decimal "latitude", precision: 10, scale: 7, null: false
    t.decimal "longitude", precision: 10, scale: 7, null: false
    t.jsonb "flight_data", default: {}, null: false
    t.jsonb "rail_data", default: {}, null: false
    t.jsonb "road_data", default: {}, null: false
    t.datetime "fetched_at"
    t.string "status", default: "pending", null: false
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["property_id"], name: "index_property_transport_snapshots_on_property_id", unique: true
    t.index ["status"], name: "index_property_transport_snapshots_on_status"
  end

  add_foreign_key "properties", "air_quality_stations"
  add_foreign_key "properties", "area_price_growths"
  add_foreign_key "properties", "boroughs"
  add_foreign_key "properties", "estate_agents"
  add_foreign_key "properties", "flood_risk_datapoints"
  add_foreign_key "property_crime_snapshots", "properties"
  add_foreign_key "property_images", "properties"
  add_foreign_key "property_nearest_stations", "properties"
  add_foreign_key "property_transport_snapshots", "properties"
end
