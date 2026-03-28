class CreatePropertyCrimeSnapshots < ActiveRecord::Migration[7.2]
  def change
    create_table :property_crime_snapshots do |t|
      t.references :property, null: false, foreign_key: true, index: { unique: true }
      t.decimal :latitude,  precision: 10, scale: 7
      t.decimal :longitude, precision: 10, scale: 7
      t.float   :avg_monthly_crimes
      t.string  :status, null: false, default: "pending"
      t.datetime :fetched_at
      t.text    :error_message
      t.timestamps
    end
  end
end
