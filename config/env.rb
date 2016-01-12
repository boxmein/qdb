#The environment variable DATABASE_URL should be in the following format:
# => postgres://{user}:{password}@{host}:{port}/path
configure :development, :production do
  db = URI.parse(ENV['DATABASE_URL'] || 'postgres://localhost')

  ActiveRecord::Base.establish_connection(
      :adapter => 'postgresql',
      :host     => db.host,
      :username => db.user,
      :password => db.password,
      :database => db.path[1..-1],
      :encoding => 'utf8'
  )
end
