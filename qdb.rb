require 'sinatra'
require 'sinatra/activerecord'
require 'will_paginate'
require 'will_paginate/active_record'
require './config/env'
require 'sinatra/recaptcha'
require 'bcrypt'

# wow models
require './models/Quote'
require './models/User'

abort "Set $COOKIE_SECRET to a cookie secret!" unless ENV['COOKIE_SECRET']
use Rack::Session::Cookie, :expire_after => 604800,
                           :secret => ENV['COOKIE_SECRET']

configure do
  set :auth_flags, {
    :post_quotes => 1,
    :edit_quotes => 2,
    :delete_quotes => 4,
    :list_users => 8,
    :approve_quotes => 16,
    :set_flags => 32,
    :edit_users => 64
  }

  set(:auth) do |*roles|
    condition do
      # new pseudo-role: logged_in
      if roles.include? :logged_in
        redirect '/user/login' unless session[:username]
        return
      end

      unless session[:username]
        redirect '/user/login'
        return
      end

      curr_flags = session[:flags]
      auth_flags = settings.auth_flags

      allowed = roles.length > 0

      roles.each do |role|
        # skip the :logged_in role
        next if role == :logged_in
        flag_exists = (curr_flags & auth_flags[role]) != 0
        allowed = allowed && flag_exists
      end
      redirect '/user/login' unless allowed
    end

    Sinatra::ReCaptcha.public_key = "6LeTMwgTAAAAAGbcCK0A3l-oKsqeHvvgzyuVO6Yz"
    abort "Set $RECAPTCHA_SECRET to your recaptcha secret!" unless ENV['RECAPTCHA_SECRET']
    Sinatra::ReCaptcha.private_key = ENV['RECAPTCHA_SECRET']
  end

  # Open a new file for moderation action logging
  $moderationLog = File.new './log/moderation.log', 'a'
  $moderationLog.sync = true

  def logModAction(name, action, on)
    time = DateTime.now.iso8601
    $moderationLog.puts "time=#{time} name=#{name} action=#{action} on=#{on}"
  end

  set :logModAction, lambda { |name, act, on| logModAction(name, act, on) }
  set :public_folder, File.dirname(__FILE__) + '/static'
  set :recaptcha_secret, ENV['RECAPTCHA_SECRET']
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

helpers do
  include Rack::Utils
  alias_method :esc, :escape_html
end

error do
  erb :error, locals: {message: env['sinatra.error'].message}
end

error 403 do
  erb :'responses/403'
end

not_found do
  erb :'responses/404'
end

#
# Viewing quotes
#

get '/' do
  erb :index
end


# Get which quote?
get '/quote/:id' do
  pass if params[:id] == 'new'
  @quote = Quote.where(:id => params[:id].to_i).first

  if (@quote && @quote.approved) or
     (@quote && @loggedIn && @userFlags.include?(:approve_quotes))
    erb :'quote/view'
  else
    404
  end
end

# Get a list of quotes with a sort-by action
get '/quotes/:sortby' do
  # pass unless params[:sortby]
  pass
end

# Get a list of ~10 quotes
get '/quotes/' do
  page = params[:page] == 0 ? 1 : params[:page]
  @quotes = Quote.where(:approved => true).page(params[:page])
  erb :'quote/list'
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


get '/user/login' do
  erb :'user/login'
end

get '/login' do
  redirect '/user/login'
end

post '/user/login' do

  unless session.empty?
    raise ErrLoggedIn
  end
  unless params[:name] and params[:password]
    raise ErrInvalidRequest
  end

  user = User.where(name: params[:name]).first

  if user
    pw_hash = BCrypt::Password.new (user[:password])

    if pw_hash == params[:password]
      session[:username] = user[:name]
      session[:flags] = user[:flags]
      session[:user_id] = user[:id]

      erb :'responses/success_logging_in'

    else
      raise ClientError, "Wrong username or password. I won't tell which >:D"
    end
  else
    404
  end
end

get '/user/register' do
  erb :'user/register'
end

post '/user/register' do

  raise InvalidRequest unless params[:user] and params[:user][:name] and params[:user][:password]
  raise ClientError, "You failed the captcha!" unless recaptcha_correct?

  params[:user][:flags] = 0
  params[:user][:password] = BCrypt::Password.create(params[:user][:password])

  user = User.new params[:user]

  if user.save
    erb :'responses/success_registering'
  else
    raise RouteError, "Error while saving new user"
  end
end

get '/register' do
  redirect '/user/register'
end

# Users can only view their own settings
get '/user/settings', :auth => [:logged_in] do
  @user = User.find(session[:user_id])

  if @user
    erb :'user/settings'
  else
    404
  end
end

get '/user/logout', :auth => [:logged_in] do
  session.clear
  erb :'responses/success_logging_out'
end

get '/logout' do
  redirect '/user/logout'
end

get '/user/change_pw', :auth => [:logged_in] do
  @user = User.find(session[:user_id])
  if @user
    erb :'user/change_pw'
  else
    404
  end
end

post '/user/change_pw', :auth => [:logged_in] do
  @user = User.find(session[:user_id])
  if @user
    # Check that the old password is right
    pw_hash = BCrypt::Password.new(@user.password)

    raise ClientError, "Incorrect password!"   unless pw_hash == params[:password]
    raise ErrPWMatch, "Passwords don't match!" unless params[:password] == params[:password_confirm]

    @user.password = BCrypt::Password.create(params[:password])

    if @user.save
      erb :'responses/success_saving', locals: {thing: 'your new password'}
    else
      raise RouteError, "Error while saving new user"
    end
  else
    404
  end
end

get '/user/delete', :auth => [:logged_in] do
  erb :'user/delete'
end

post '/user/delete', :auth => [:logged_in] do
  @user = User.find(session[:user_id])
  if @user
    @user.destroy
    session.clear
    erb :'responses/success_deleting_user'
  else
    404
  end
end

get '/user/:id/edit', :auth => [:edit_users] do
  @user = User.find(params[:id])
  if @user
    erb :'user/edit'
  else
    404
  end
end

post '/user/:id/edit', :auth => [:edit_users] do
  @user = User.find(params[:id])
  if @user
    u = params[:user]
    @user.id = u[:id]
    @user.name = u[:name]
    @user.password = u[:password]
    if @user.save
      erb :'responses/success_saving', locals: {thing: 'user', extra: u[:name]}
    else
      raise RouteError, "Error while saving edited user"
    end
  else
    404
  end
end

#
# Managing quotes
#

get '/quote/new', :auth => [:post_quotes] do
  erb :'quote/add'
end

# Post a new quote, returns link to quote
post '/quote/new', :auth => [:post_quotes] do
  q = params[:quote]

  # no double escaping now!
  # make sure that quote.erb et al keep esc()ing the input then
  # q[:quote]  = esc(q[:quote])
  q[:author] = session[:username]

  mdl = Quote.new q

  if mdl.save
    logModAction(session[:username], ":post_quotes", mdl[:id])
    redirect '/quotes/'
  else
    raise RouteError, "Error while saving new quote"
  end
end


# Edit/Delete a quote by ID

get '/quote/:id/edit', :auth => [:edit_quotes] do

  @action = "edit"
  @quote = Quote.find(params[:id].to_i)

  if @quote
    erb :'quote/edit'
  else
    404
  end
end

post '/quote/:id/edit', :auth => [:edit_quotes] do
  unless params[:author] and params[:quote]

  end
  quote = Quote.find(params[:id].to_i)

  if quote
    quote.author = params[:author]
    quote.quote  = params[:quote]
    if quote.save
      logModAction(session[:username], ":edit_quotes", params[:id].to_i)
      redirect "/quote/#{params[:id]}"
    else
      raise RouteError, "Error while saving edited quote"
    end
  end
end


get '/quote/:id/delete', :auth => [:delete_quotes] do

  @quote = Quote.find(params[:id].to_i)

  if @quote
    erb :'quote/delete'
  else
    404
  end
end

post '/quote/:id/delete', :auth => [:delete_quotes] do

  quote = Quote.find(params[:id].to_i)

  if quote
    logModAction(session[:username], ":delete_quotes", params[:id].to_i)
    quote.destroy
    erb "<h2> Destroyed quote #{params[:id]} successfully. </h2>"
  else
    raise RouteError, "Error while deleting quote"
  end
end

post '/quote/:id/approve', :auth => [:approve_quotes] do
  quote = Quote.find(params[:id].to_i)
  if quote
    quote.approved = true
    if quote.save
      erb :'responses/success_saving', locals: {thing: 'quote', extra: params[:id]}
    else
      raise RouteError, "Error while saving new approved quote"
    end
  else
    404
  end
end


#
# Managing users
#

get '/user/list', :auth => [:list_users] do
  page = params[:page] == 0 ? 1 : params[:page]
  @users = User.all.order(:id).page(page)
  erb :'user/list'
end

get '/user/:id/set_flags', :auth => [:set_flags] do
  @id = params[:id]
  user = User.find(params[:id])
  @username = user.name
  @userflags = user.flags
  erb :'user/set_flags'
end

post '/user/:id/set_flags', :auth => [:set_flags] do
  raise InvalidRequest unless params[:flags]

  user = User.find(params[:id])

  if user
    user[:flags] = params[:flags].to_i
    if user.save
      logModAction(session[:username], ":set_flags","#{params[:id]} -> #{user[:flags]}")
      erb :'responses/success_saving', locals: {thing: 'user flags for', extra: user[:name]}
    else
      raise RouteError, "Error while saving"
    end
  else
    404
  end
end

# Moderation queue
get '/moderate/queue', :auth => [:approve_quotes] do
  @quotes = Quote.where(:approved => false).order(:id).page(params[:page])
  erb :'mod/approve_queue'
end


#
# Errors
#

class ClientError < StandardError; end
class RouteError < StandardError; end
class InvalidRequest < StandardError; end

error InvalidRequest do
  status 401
  body(erb(:error, locals: {message: <<-EOF
  <b>Invalid request body!</b>
  <p>If you're doing API calls, try not missing any inputs. Otherwise, well,
  bad luck! Here's maybe an error message.</b>
  <pre><code>#{env['sinatra.error'].message}</pre></code>
  EOF
  }))
end

error RouteError do
  status 500
  body(erb(:error, locals: {message: env['sinatra.error'].message}))
end

error ClientError do
  status 401
  body(erb(:error, locals: {message: env['sinatra.error'].message}))
end
