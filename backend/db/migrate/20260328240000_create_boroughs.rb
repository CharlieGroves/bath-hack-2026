class CreateBoroughs < ActiveRecord::Migration[7.2]
  def change
    create_table :boroughs do |t|
      # Canonical name matching the NTE dataset (e.g. "Westminster", "Camden")
      t.string  :name,      null: false

      # Night-time economy business count (2017, "Any NTE category")
      t.float   :nte_score_raw
      # Min-max normalised to [0, 1]
      t.float   :nte_score, null: false

      t.timestamps
    end

    add_index :boroughs, :name, unique: true
  end
end
