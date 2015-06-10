class User < ActiveRecord::Base
  validates_presence_of :password, :on => :create
end
