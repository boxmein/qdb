require 'bcrypt'
class User < ActiveRecord::Base
  validates_presence_of :password, :on => :create
  def pw
    @pw ||= BCrypt::Password.new self.password
  end

  def pw=(new_password)
    @pw = BCrypt::Password.create new_password
    self.password = @pw
  end
end
