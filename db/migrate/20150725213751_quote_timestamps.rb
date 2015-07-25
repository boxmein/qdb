class QuoteTimestamps < ActiveRecord::Migration
  def change
    change_table :quotes do |t|
      t.timestamps null: true
    end
  end
end
