class CreateQuote < ActiveRecord::Migration
  def up
    create_table :quotes do |t|
      t.string :author
      t.string :quote
    end
  end

  def down
    drop_table :quotes
  end
end
