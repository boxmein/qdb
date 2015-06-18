class AddVoteNumbers < ActiveRecord::Migration
  def change
    add_column :quotes, :upvotes, :integer
    add_column :quotes, :downvotes, :integer
  end
end
