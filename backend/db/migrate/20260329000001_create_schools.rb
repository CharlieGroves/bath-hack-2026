class CreateSchools < ActiveRecord::Migration[7.2]
  def change
    create_table :schools do |t|
      # DfE unique reference number — stable identifier across datasets
      t.string  :urn,       null: false

      t.string  :name,      null: false
      t.string  :address1
      t.string  :address2
      t.string  :town
      t.string  :postcode,  null: false

      # KS4 Progress 8 measure (2023-24, sourced from P8MEA_PREV in 2024-25 file)
      # Range roughly -4 to +4; positive = above national average
      t.float   :p8mea

      # Geocoded from postcode via Nominatim
      t.decimal :latitude,  precision: 10, scale: 7
      t.decimal :longitude, precision: 10, scale: 7

      t.timestamps
    end

    add_index :schools, :urn,      unique: true
    add_index :schools, :postcode
    add_index :schools, [:latitude, :longitude]
  end
end
