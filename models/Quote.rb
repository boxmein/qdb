class Quote < ActiveRecord::Base
  validates :quote, presence: true
  validates :quote, length: {maximum: 1000}
  validates :upvotes, numericality: { only_integer: true }
  has_many :votes
  has_many :voters, :through => :votes, source: :user, :class_name => 'User'
end
