class CreateProperties < ActiveRecord::Migration[7.2]
  def change
    create_table :properties do |t|
      # Core identity
      t.string   :rightmove_id,                null: false
      t.string   :slug,                        null: false
      t.string   :listing_url

      # Listing content
      t.string   :title
      t.text     :description
      t.jsonb    :key_features,                default: [], null: false
      t.jsonb    :photo_urls,                  default: [], null: false

      # Price
      t.integer  :price_pence
      t.string   :price_qualifier
      t.integer  :price_per_sqft_pence

      # Property attributes
      t.string   :property_type
      t.integer  :bedrooms
      t.integer  :bathrooms
      t.integer  :size_sqft

      # Tenure
      t.string   :tenure
      t.integer  :lease_years_remaining

      # Running costs
      t.string   :epc_rating
      t.string   :council_tax_band
      t.integer  :service_charge_annual_pence

      # Location
      t.string   :address_line_1
      t.string   :town
      t.string   :postcode
      t.decimal  :latitude,                    precision: 10, scale: 7
      t.decimal  :longitude,                   precision: 10, scale: 7

      # Agent
      t.string   :agent_name
      t.string   :agent_phone

      # Media flags
      t.boolean  :has_floor_plan,              default: false, null: false
      t.boolean  :has_virtual_tour,            default: false, null: false

      # Free-text fields (not filterable)
      t.string   :utilities_text
      t.string   :parking_text

      # Lifecycle
      t.string   :status,                      default: "active", null: false
      t.datetime :listed_at
      t.datetime :last_seen_at

      # Raw scraped payload for re-parsing
      t.jsonb    :raw_data

      t.timestamps
    end

    add_index :properties, :rightmove_id, unique: true
    add_index :properties, :slug,         unique: true
    add_index :properties, :postcode
    add_index :properties, :status
    add_index :properties, :price_pence
    add_index :properties, :bedrooms
    add_index :properties, [:latitude, :longitude]
    add_index :properties, :listed_at
    add_index :properties, :property_type
    add_index :properties, :tenure
  end
end
