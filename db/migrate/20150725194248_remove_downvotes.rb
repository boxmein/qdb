class RemoveDownvotes < ActiveRecord::Migration
  def change
    remove_column :quotes, :downvotes
  end
end
