class AddBoroughToProperties < ActiveRecord::Migration[7.2]
  def change
    add_reference :properties, :borough,
                  null: true,
                  foreign_key: true,
                  index: true
  end
end
