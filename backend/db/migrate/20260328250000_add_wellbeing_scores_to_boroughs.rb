class AddWellbeingScoresToBoroughs < ActiveRecord::Migration[7.2]
  def change
    add_column :boroughs, :life_satisfaction_score_raw, :float unless column_exists?(:boroughs, :life_satisfaction_score_raw)
    add_column :boroughs, :life_satisfaction_score,     :float unless column_exists?(:boroughs, :life_satisfaction_score)
    add_column :boroughs, :happiness_score_raw,         :float unless column_exists?(:boroughs, :happiness_score_raw)
    add_column :boroughs, :happiness_score,             :float unless column_exists?(:boroughs, :happiness_score)
    add_column :boroughs, :anxiety_score_raw,           :float unless column_exists?(:boroughs, :anxiety_score_raw)
    add_column :boroughs, :anxiety_score,               :float unless column_exists?(:boroughs, :anxiety_score)
  end
end
