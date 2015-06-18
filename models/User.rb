require 'bcrypt'
class User < ActiveRecord::Base
  validates :name, presence: true
  validates :password, presence: true

  validates :name, format: {with: /\A[A-Za-z0-9\-_.]+\z/, message: 'The username contains invalid characters! Use /A-Za-z0-9-_./'}
  validates :name, length: {minimum: 4, maximum: 16, message: 'The username is not the right size! Try 4-16 characters.'}
  validates :name, uniqueness: {case_sensitive: false, message: 'The username has already been taken! Try another one!'}
  validates :flags, numericality: {only_integer: true, message: 'The new flags were not a valid number.'}

  has_many :votes, :through => :votes

  def pw
    @pw ||= BCrypt::Password.new self.password
  end

  def pw=(new_password)
    @pw = BCrypt::Password.create new_password
    self.password = @pw
  end
end
