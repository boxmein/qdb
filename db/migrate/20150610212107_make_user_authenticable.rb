class MakeUserAuthenticable < ActiveRecord::Migration
  def change
    change_table :users do |t|
      t.rename :hash, :password
    end
  end
end
