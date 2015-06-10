class HideUnapprovedQuotes < ActiveRecord::Migration
  def change
    add_column :quotes, :approved, :boolean, :default => false
  end
end
