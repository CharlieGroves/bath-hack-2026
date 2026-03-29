class AddIsSharedOwnershipToProperties < ActiveRecord::Migration[7.2]
  def up
    add_column :properties, :is_shared_ownership, :boolean, default: false, null: false
    add_index :properties, :is_shared_ownership

    execute <<~SQL.squish
      UPDATE properties
      SET is_shared_ownership = TRUE
      WHERE description ~* '(shared\\s+ownership|part[-\\s]*buy[-\\s]*part[-\\s]*rent|([1-9][0-9]?(?:\\.[0-9]+)?)\\s*%\\s*(share|shared|ownership|of(?:\\s+the)?\\s+property)|(share|ownership)\\s*(purchase|available|to\\s+buy|being\\s+sold)?\\s*:?\\s*([1-9][0-9]?(?:\\.[0-9]+)?)\\s*%)'
    SQL
  end

  def down
    remove_index :properties, :is_shared_ownership
    remove_column :properties, :is_shared_ownership
  end
end
