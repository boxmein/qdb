class Quote < ActiveRecord::Base
  validates :quote, presence: true
  validates :quote, length: {maximum: 1000}
  has_many :voters, :through => :votes, :class_name => 'User'
end
