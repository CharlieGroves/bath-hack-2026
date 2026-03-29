class CreateModelSearches < ActiveRecord::Migration[7.2]
  def change
    create_table :model_searches do |t|
      t.text    :prompt,     null: false
      t.string  :status,     null: false, default: "pending"   # pending | complete | failed
      t.jsonb   :filters,    null: false, default: {}           # params parsed from LLM response
      t.jsonb   :result_ids, null: false, default: []           # ordered property IDs
      t.text    :error_message

      t.timestamps
    end

    add_index :model_searches, :status
  end
end
