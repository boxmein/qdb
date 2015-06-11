require 'sinatra'
require 'sinatra/activerecord'
require './config/env'

require 'bcrypt'

# wow models
require './models/Quote'
require './models/User'

configure do
  enable :sessions

  set :auth_flags, {
    :post_quotes => 1,
    :edit_quotes => 2,
    :delete_quotes => 4,
    :list_users => 8,
    :approve_quotes => 16,
    :set_flags => 32
  }

  set(:auth) do |*roles|
    condition do
      redirect '/login' unless session[:username]

      curr_flags = session[:flags]
      auth_flags = settings.auth_flags

      allowed = roles.length > 0

      roles.each do |role|
        flag_exists = (curr_flags & auth_flags[role]) != 0
        allowed = allowed && flag_exists
      end
      redirect '/login' unless allowed
    end
  end

  # Open a new file for moderation action logging
  $moderationLog = File.new './log/moderation.log', 'a'
  $moderationLog.sync = true

  def logModAction(name, action, on)
    time = DateTime.now.iso8601
    $moderationLog.puts "time=#{time} name=#{name} action=#{action} on=#{on}"
  end

  set :logModAction, lambda { |name, act, on| logModAction(name, act, on) }

end

before do
  @username = session[:username] or nil
  @loggedIn = @username != nil
  @flags    = session[:flags]

  if @loggedIn
    @userFlags = []
    settings.auth_flags.each do |flag, bitmask|
      if (session[:flags] & bitmask) != 0
        @userFlags << flag
      end
    end
  end
end


#
# Viewing quotes
#

get '/' do
  erb :index
end


# Get which quote?
get '/quote/:id' do
  @quote = Quote.where(:id => params[:id].to_i).first

  if @quote
    erb :quote
  else
    erb :error, locals: { message: "No such quote!" }
  end
end

# Get a list of quotes with a sort-by action
get '/quotes/:sortby' do
  pass unless params[:sortby]
end

# Get a list of ~10 quotes
get '/quotes/' do
  @quotes = Quote.all
  erb :quotes
end

get '/quote' do
  redirect '/quotes/'
end

get '/quotes' do
  redirect '/quotes/'
end

#
# Logins
#

get '/login' do
  erb :login
end

post '/login' do

  unless params[:name] and params[:password]
    erb :error, locals: {message: "Invalid request body!"}
  end

  user = User.where(name: params[:name]).first

  if user
    pw_hash = BCrypt::Password.new (user[:password])

    if pw_hash == params[:password]
      session[:username] = user[:name]
      session[:flags] = user[:flags]

      erb "<h2> Successfully logged in as #{user.name}! </h2>"
    end
  else
    erb :error, locals: { message: "User/password invalid :(" }
  end
end

get '/register' do
  erb :register
end

post '/register' do
  unless params[:user] and params[:user][:name] and params[:user][:password]
    erb :error, locals: {message: "Invalid request body!"}
  end

  puts "Creating new user with details:"
  p params[:user]

  # TODO: disable users setting their own flags
  params[:user][:flags] = 0
  # params[:user][:flags] = params[:user][:flags].to_i
  params[:user][:password] = BCrypt::Password.create(params[:user][:password])

  user = User.new params[:user]

  if user.save
    puts "Success!"
    erb "<h2>Successfully registered with username #{params[:user][:name]}!</h2>"
  else
    puts "Failure!"
    erb :error, locals: {message: "Error saving your user!"}
  end
end

get '/logout' do
  session.clear
  erb "<h2> Session cleared! </h2>"
end


#
# Managing quotes
#

# Post a new quote, returns link to quote
post '/quote/new', :auth => [:post_quotes] do
  q = params[:quote]

  q[:author] = session[:username]

  mdl = Quote.new q

  if mdl.save
    logModAction(session[:username], ":post_quotes", mdl[:id])
    redirect '/quotes/'
  else
    erb :error, locals: { message: "Error saving the quote!" }
  end
end


# Edit/Delete a quote by ID

get '/quote/:id/edit', :auth => [:edit_quotes] do

  @action = "edit"
  @quote = Quote.find(params[:id].to_i)

  if @quote
    erb :edit_quote
  else
    erb :error, locals: { message: "No such quote!" }
  end
end

post '/quote/:id/edit', :auth => [:edit_quotes] do
  unless params[:author] and params[:quote]
    erb :error, locals: {message: "Invalid form data!"}
  end
  quote = Quote.find(params[:id].to_i)

  if quote
    quote.author = params[:author]
    quote.quote  = params[:quote]
    if mdl.save
      logModAction(session[:username], ":edit_quotes", params[:id].to_i)
      redirect "/quote/#{params[:id]}"
    else
      erb :error, locals: { message: "Error saving quote!" }
    end
  end
end


get '/quote/:id/delete', :auth => [:delete_quotes] do

  @action = "delete"
  @quote = Quote.find(params[:id].to_i)

  if @quote
    erb :edit_quote
  else
    erb :error, locals: { message: "No such quote!" }
  end
end

post '/quote/:id/delete', :auth => [:delete_quotes] do

  quote = Quote.find(params[:id].to_i)

  if quote
    logModAction(session[:username], ":delete_quotes", params[:id].to_i)
    quote.destroy
    erb "<h2> Destroyed quote #{params[:id]} successfully. </h2>"
  else
    erb :error, locals: { message: "Error deleting quote!" }
  end
end


#
# Managing moderators
#

get '/list_users', :auth => [:list_users] do
  @users = User.all
  erb :users
end

get '/set_flags/:user', :auth => [:set_flags] do
  @user = params[:user]
  erb :set_flags
end

post '/set_flags/:user', :auth => [:set_flags] do
  unless params[:flags]
    erb :error, locals: {message: "Invalid form data! 'flags' needed!"}
  end

  user = User.where(:name => params[:user]).first

  if user
    user[:flags] = params[:flags].to_i
    if user.save
      logModAction(session[:username], ":set_flags", params[:user] + " -> " + user[:flags])
      erb "<h2> Successfully saved new flags #{user[:flags]} to user #{user[:name]}"
    else
      erb :error, locals: {message: "Error saving user!"}
    end
  else
    erb :error, locals: {message: "No such user!"}
  end
end

# Moderation queue
get '/modq', :auth => [:approve_quotes] do

end
