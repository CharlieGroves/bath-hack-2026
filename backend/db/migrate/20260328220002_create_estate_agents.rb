class CreateEstateAgents < ActiveRecord::Migration[7.2]
  def change
    create_table :estate_agents do |t|
      t.string :lookup_key, null: false
      t.string :google_place_id, null: false
      t.string :display_name
      t.decimal :rating, precision: 2, scale: 1

      t.timestamps
    end

    add_index :estate_agents, :lookup_key, unique: true
    add_index :estate_agents, :google_place_id, unique: true

    add_reference :properties, :estate_agent, foreign_key: true, null: true
  end
end
