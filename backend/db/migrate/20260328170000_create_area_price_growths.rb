class CreateAreaPriceGrowths < ActiveRecord::Migration[7.2]
  def change
    create_table :area_price_growths do |t|
      t.string :area_slug, null: false
      t.string :area_name, null: false
      t.jsonb :yearly_growth_data, null: false, default: {}

      t.timestamps
    end

    add_index :area_price_growths, :area_slug, unique: true
    add_reference :properties, :area_price_growth, foreign_key: true
  end
end
