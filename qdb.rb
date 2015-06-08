require 'sinatra'
require 'sinatra/activerecord'
require './config/environments'

set(:auth) do |*roles|
  condition do
    unless logged_in? && roles.any? {|role| }

end

# Quote display options, intro text
get '/' do

end

# Get which quote?
get '/quote/:id' do
  "Hello #{params[:id]}"
end

# Post a new quote, returns link to quote
post '/quote/new', :auth => [:post_comments] do
  "New quote:"
end

# Post a quote with ID :id and KeyID :keyid - allows quotes to be overridden
put '/quote/:id', :auth => [:post_comments] do

end

# Delete a quote
delete '/quote/:id', :auth => [:post_comments] do

end

# Get a list of ~10 quotes
get '/quotes/:sortby' do

end


# Moderator queue
get '/modlog', :auth => [:approve_comments] do

end


get // do
  redirect '/404/'
end
