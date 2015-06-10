class AddIds < ActiveRecord::Migration
  def change
    add_index :quotes, :id
  end
end
