class ChangePenceColumnsToBigint < ActiveRecord::Migration[7.2]
  def change
    change_column :properties, :price_pence,                :bigint
    change_column :properties, :price_per_sqft_pence,       :bigint
    change_column :properties, :service_charge_annual_pence, :bigint
  end
end
