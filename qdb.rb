require 'sinatra'
require 'sinatra/activerecord'
require './config/env'

# wow models
require './models/Quote'

# Quote display options, intro text
get '/' do
  erb :index
end

# Get which quote?
get '/quote/:id' do
  erb :quote, locals: { id: params[:id] }
end

# Post a new quote, returns link to quote
post '/quote/new' do
  q = params[:quote]
  puts "New quote by " + q[:author]
  puts q[:quote]

  mdl = Quote.new q

  if mdl.save
    redirect '/quotes/'
  else
    "Errors & stuff :("
  end
end

# Get a list of ~10 quotes
get '/quotes/' do
  @quotes = Quote.all
  erb :quotes
end

# Edit a quote by ID
put '/quote/:id' do end

# Delete a quote
delete '/quote/:id' do end

# Get a list of quotes with a sort-by action
get '/quotes/:sortby' do end

# Moderator activity log
get '/modlog' do end

# Moderation queue
get '/modq' do end
