class AddWellbeingScoresToBoroughs < ActiveRecord::Migration[7.2]
  def change
    add_column :boroughs, :life_satisfaction_score_raw, :float
    add_column :boroughs, :life_satisfaction_score,     :float
    add_column :boroughs, :happiness_score_raw,         :float
    add_column :boroughs, :happiness_score,             :float
    add_column :boroughs, :anxiety_score_raw,           :float
    add_column :boroughs, :anxiety_score,               :float
  end
end
