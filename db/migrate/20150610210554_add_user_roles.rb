class AddUserRoles < ActiveRecord::Migration
  def change
    add_column :users, :flags, :integer
  end
end
