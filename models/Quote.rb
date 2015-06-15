class Quote < ActiveRecord::Base
  validates :quote, presence: true
  validates :quote, length: {maximum: 1000}
end
