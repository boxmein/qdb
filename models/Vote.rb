class Vote < ActiveRecord::Base
  belongs_to :quote
  belongs_to :user

  validates :user_id, uniqueness: { :scope => :quote_id }
end
