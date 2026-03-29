class CreatePropertyMonthlyBillEstimates < ActiveRecord::Migration[7.2]
  def change
    create_table :property_monthly_bill_estimates do |t|
      t.references :property, null: false, foreign_key: true, index: { unique: true }
      t.string :provider, null: false, default: "openai"
      t.string :model_name, null: false, default: "gpt-4o-mini"
      t.string :status, null: false, default: "pending"
      t.bigint :estimated_total_monthly_pence
      t.string :confidence
      t.text :assumptions
      t.jsonb :breakdown, null: false, default: {}
      t.jsonb :raw_payload, null: false, default: {}
      t.datetime :fetched_at
      t.text :error_message

      t.timestamps
    end

    add_index :property_monthly_bill_estimates, :status
  end
end
