require 'sinatra'
require 'sinatra/activerecord'
require 'will_paginate'
require 'will_paginate/active_record'
require './config/env'
require 'sinatra/recaptcha'
require 'bcrypt'
require 'rack-flash'
require 'json'
require 'encrypted_cookie'
require 'rack/csrf'

# wow models
require './models/Quote'
require './models/User'
require './models/Vote'

abort "Set $COOKIE_SECRET to a cookie secret!" unless ENV['COOKIE_SECRET']
use Rack::Session::EncryptedCookie, :expire_after => 604800,
                                    :secret => ENV['COOKIE_SECRET'],
                                    :http_only => true
use Rack::Csrf, :alert => true, :skip => ['POST:/upvote/\\d+']
use Rack::Flash, :accessorize => [:info, :success, :error]

configure do
  set :auth_flags, {
    :post_quotes => 1,
    :edit_quotes => 2,
    :delete_quotes => 4,
    :list_users => 8,
    :approve_quotes => 16,
    :set_flags => 32,
    :edit_users => 64,
    :can_vote => 128
  }

  # cookies time out after 7 days
  set :cookie_timeout, 604800

  set(:auth) do |*roles|
    condition do

      # secondary cookie expiration
      unless session[:timestamp]
        flash[:info] = 'You need to relogin to update your session!'
        session.clear
        unless request.xhr? 
          redirect '/user/login'
        else
          status 401
          body(JSON.fast_generate({success: false, err: 'ADD_TIMESTAMP'}))
        end
        break
      else
        begin
          ctime = Time.at session[:timestamp]
          ntime = Time.now

          if (ntime - ctime) > settings.cookie_timeout
            flash[:info] = 'Session expired. Please relogin'
            session.clear
            unless request.xhr?
              redirect '/user/login?' + Rack::Utils.build_query({ :next => request.path }) unless request.xhr?
            else
              status 401
              body(JSON.fast_generate({success: false, err: 'SESSION_EXPIRED'})) 
            end
            break
          end
        rescue TypeError
          flash[:error] = 'Invalid timestamp - please relogin!'
          session.clear
          unless request.xhr?
            redirect '/user/login?' + Rack::Utils.build_query({ :next => request.path }) unless request.xhr?
          else
            status 401 
            body(JSON.fast_generate({success: false, err: 'INVALID_TIMESTAMP'})) 
          end
          break
        end
      end


      # new pseudo-role: logged_in
      if roles.include? :logged_in
        unless session[:username]
          flash[:error] = 'You need to be logged in to go here.'
          unless request.xhr?
            redirect '/user/login?' + Rack::Utils.build_query({ :next => request.path })
          else
            status 401
            body(JSON.fast_generate({success: false, err: 'NOT_LOGGED_IN'}))
          end
        end
        break
      end

      unless session[:username]
        flash[:error] = 'You need to be logged in to go here.'
        unless request.xhr?
          redirect '/user/login?' + Rack::Utils.build_query({ :next => request.path })
        else
          status 401
          body(JSON.fast_generate({success: false, err: 'NOT_LOGGED_IN'}))
        end
        break
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

      unless allowed
        if request.xhr?
          status 401
          body(JSON.fast_generate({success: false, err: 'UNAUTHORIZED'}))
        else
          flash[:error] = 'You aren\'t allowed to go here! :('
          redirect '/'
        end
      end
    end

    abort "Set $RECAPTCHA_CLIENTKEY to your recaptcha public/client key!" unless ENV['RECAPTCHA_CLIENTKEY']
    Sinatra::ReCaptcha.public_key = ENV['RECAPTCHA_CLIENTKEY']

    abort "Set $RECAPTCHA_SECRET to your recaptcha secret!" unless ENV['RECAPTCHA_SECRET']
    Sinatra::ReCaptcha.private_key = ENV['RECAPTCHA_SECRET']
  end

  # Mod logs are now also stdout
  def logModAction(name, action, on)
    puts "modaction name=#{name} action=#{action} on=#{on}"
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

  response.headers['Content-Security-Policy'] = "default-src 'self'; script-src 'self' https://ajax.googleapis.com https://maxcdn.bootstrapcdn.com https://cdnjs.cloudflare.com; style-src 'self' https://maxcdn.bootstrapcdn.com https://cdnjs.cloudflare.com; font-src 'self' https://maxcdn.bootstrapcdn.com https://cdnjs.cloudflare.com"
  response.headers['X-Frame-Options'] = 'deny'
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
  redirect '/quotes' if params[:id] == 'list'
  @quote = Quote.where(:id => params[:id].to_i).first
  
  user = User.where(name: session[:username]).first
  @voted = Vote.where(quote: @quote, user: user).first != nil

  if (@quote && @quote.approved) or
     (@quote && @loggedIn && @userFlags.include?(:approve_quotes))
    erb :'quote/quote_view'
  else
    flash[:error] = 'There is no quote with this ID!'
    redirect '/quotes/'
  end
end

# Get a list of ~40 quotes
get '/quotes/' do
  page = params[:page] == 0 ? 1 : params[:page]
  @quotes = Quote.where(:approved => true).order(:id).page(params[:page])

  user = User.where(name: session[:username]).first
  @votedQuotes = Vote.where(user: user).to_a.map(&:quote_id)

  puts "quotes the user has voted on"
  p @votedQuotes

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

  if session[:username] and session[:user_id] and session[:flags]
    flash[:info] = 'You\'re already logged in!'
    redirect(request.params[:next] ? request.params[:next] : '/')
  end

  unless params[:name] and params[:password]
    raise InvalidRequest, 'Missing parameters when trying to log in.'
  end

  # process the username a bit
  params[:name].strip!

  user = User.where(name: params[:name]).first

  if user
    if user.pw == params[:password]
      session[:username] = user[:name]
      session[:flags] = user[:flags]
      session[:user_id] = user[:id]
      session[:timestamp] = Time.now.to_i

      flash[:success] = 'Successfully logged in!'
      redirect(request.params[:next] ? request.params[:next] : '/')

    else
      flash[:error] = 'Invalid username or password.'
      redirect '/user/login'
    end
  else
    flash[:error] = 'Invalid username or password.'
    redirect '/user/login'
  end
end

#
# Registrations
#

get '/user/register' do
  response.headers['Content-Security-Policy'] = ''
  erb :'user/register'
end

post '/user/register' do

  raise InvalidRequest unless params[:user] and params[:user][:name] and params[:user][:password]

  params[:user][:name].strip!
  unless params[:user][:name] != '' and params[:user][:name].length > 4 and params[:user][:name].length < 16
    flash[:error] = 'The username has to stay between 4 and 16 characters. Some letters may count as more than one character!'
    redirect '/user/register'
    break
  end

  unless recaptcha_correct?
    flash[:error] = 'You failed the recaptcha! Ahem, sorry, 011000010111001001100101001000000111100101101111011101010010000001100001001000000111001001101111011000100110111101110100'
    redirect '/user/register'
    break
  end

  params[:user][:flags] = 0
  params[:user][:password] = BCrypt::Password.create(params[:user][:password])

  # username checking is now in models/User

  user = User.new params[:user]

  unless user.invalid?
    if user.save
      flash[:success] = 'Successfully registered! You can now log in.'
      redirect '/user/login'
    else
      flash[:error] = 'Failed to save the user. Try again?'
      redirect '/user/register'
    end
  else
    @errors = user.errors.messages
    erb :'user/register'
  end
end

get '/register' do
  redirect '/user/register'
end

#
# User management
#

# Users can only view their own settings
get '/user/settings', :auth => [:logged_in] do
  @user = User.find(session[:user_id])

  if @user
    erb :'user/settings'
  else
    404
  end
end

get '/user/logout' do
  session.clear
  flash[:info] = 'You are now logged out!'
  redirect(request.params[:next] ? request.params[:next] : '/')
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
    if @user.pw == params[:old_password]

      if params[:old_password] == params[:password_confirm]
        flash[:error] = 'Your passwords didn\'t match!'
        redirect '/user/change_pw'
      else
        @user.pw = params[:password]
        if @user.save
          flash[:success] = 'Successfully changed your password!'
          redirect(request.params[:next] ? request.params[:next] : '/user/settings')
        else
          flash[:error] = 'Error while saving the password!'
          redirect '/user/change_pw'
        end
      end
    else
      flash[:error] = 'Invalid password!'
      redirect '/user/change_pw'
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
    flash[:success] = 'Successfully deleted your user!'
    redirect(request.params[:next] ? request.params[:next] : '/')
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
    @user.name = esc u[:name]
    @user.password = u[:password]
    if @user.save
      flash[:success] = 'Successfully edited the user!'
      redirect(request.params[:next] ? request.params[:next] : '/user/list')
    else
      flash[:error] = 'Error saving the user!'
      redirect request.path_info
    end
  else
    flash[:error] = 'No such user!'
    redirect request.path_info
  end
end

post '/user/:id/delete', :auth => [:edit_users] do
  @user = User.find(params[:id])
  if @user
    @user.destroy
    logModAction(session[:username], ":edit_users/delete", params[:id])
    flash[:success] = "Successfully deleted the user #{@user.name}"
    session.clear if @user.name == session[:username]
    redirect(request.params[:next] ? request.params[:next] : '/user/list')
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
  q[:quote]  = esc q[:quote]
  q[:author] = esc session[:username]
  q[:upvotes] = 0

  mdl = Quote.new q

  if mdl.save
    logModAction(session[:username], ":post_quotes", mdl[:id])
    flash[:success] = 'Successfully posted the new quote!'
    redirect(request.params[:next] ? request.params[:next] : '/quotes/')
  else
    flash[:error]  = 'Error saving the new quote!'
    redirect(request.params[:next] ? request.params[:next] : '/quotes/')
  end
end


# Edit/Delete a quote by ID

get '/quote/:id/edit', :auth => [:edit_quotes] do

  @action = "edit"
  @quote = Quote.find(params[:id].to_i)

  if @quote
    erb :'quote/edit'
  else
    flash[:error] = 'No such quote!'
    redirect "/quote/#{params[:id]}"
  end
end

post '/quote/:id/edit', :auth => [:edit_quotes] do
  raise InvalidRequest unless params[:author] and params[:quote]

  quote = Quote.find(params[:id].to_i)

  if quote
    quote.author = esc params[:author]
    quote.quote  = esc params[:quote]
    if quote.save
      logModAction(session[:username], ":edit_quotes", params[:id].to_i)
      flash[:success] = 'Successfully edited the quote'
      redirect "/quote/#{params[:id]}"
    else
      flash[:error] ='Failed to save the new quote. Try again..?'
      redirect "/quote/#{params[:id]}/edit"
    end
  else
    flash[:error] = 'No such quote!'
    redirect "/quote/#{params[:id]}"
  end
end


get '/quote/:id/delete', :auth => [:delete_quotes] do

  @quote = Quote.find(params[:id].to_i)

  if @quote
    erb :'quote/delete'
  else
    flash[:error] = 'No such quote!'
    redirect '/quotes/'
  end
end

post '/quote/:id/delete', :auth => [:delete_quotes] do

  quote = Quote.find(params[:id].to_i)

  if quote
    logModAction(session[:username], ":delete_quotes", params[:id].to_i)
    quote.destroy
    flash[:success] = 'Quote destroyed successfully.'
    redirect '/quotes/'
  else
    flash[:error] = 'No such quote!'
    redirect '/quotes/'
  end
end

post '/quote/:id/approve', :auth => [:approve_quotes] do
  quote = Quote.find(params[:id].to_i)
  if quote
    quote.approved = true
    if quote.save
      flash[:success] = 'Successfully approved this quote!'
      redirect '/moderate/queue'
    else
      flash[:error] = 'Error approving this quote.'
      redirect '/moderate/queue'
    end
  else
    flash[:error] = 'No such quote!'
    redirect '/moderate/queue'
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
      flash[:success] = 'Successfully saved user flags! Updated session flags too!'
      redirect '/user/list'
    else
      flash[:error] = 'Failed to save user flags!'
      redirect '/user/list'
    end
  else
    flash[:error] = 'No such user!'
    redirect '/user/list'
  end
end

# Moderation queue
get '/moderate/queue', :auth => [:approve_quotes] do
  @quotes = Quote.where(:approved => false).order(:id).page(params[:page])
  erb :'mod/approve_queue'
end

#
# Voting
#

post '/upvote/:id', :auth => [:can_vote] do
  quote = Quote.find(params[:id])
  user = User.find(session[:user_id])

  if quote

    # TODO: check vote for uniqueness before generating new one

    existing_vote = Vote.where(:quote => quote, :user => user)

    unless existing_vote.size == 0
      puts "found existing vote on #{quote.id} by #{user.id}, skipping"
      status 401
      if request.xhr?
        body(JSON.fast_generate({success: false, votes_now: quote.upvotes, quote_id: quote.id, err: "VOTED_ALREADY"}))
      else
        flash[:error] = 'You have voted already on this quote!'
        redirect(request.params[:next] ? request.params[:next] : '/quotes/')
      end
      break
    end

    v = Vote.new
    v.quote = quote
    v.user = user
    

    if v.save
      quote.upvotes = quote.voters.size
      if quote.save
        status 200
        if request.xhr?
          body(JSON.fast_generate({success: true, votes_now: quote.upvotes, quote_id: quote.id}))
        else
          redirect '/quotes/'
        end
      else
        puts "failed to update upvote count, but vote object still remains!"
      end
    else
      if request.xhr?
        status 500
        body(JSON.fast_generate({success: false, err: 'GENERAL_FAIL', votes_now: quote.upvotes, quote_id: quote.id}))
      else
        flash[:error] = "Saving the vote failed :("
        redirect "/quote/#{params[:id]}"
      end
    end
  else
    if request.xhr?
      status 404
      body "No such quote!"
    else
      flash[:error] = 'No such quote!'
      redirect(request.params[:next] ? request.params[:next] : '/quotes/')
    end
  end
end

post '/unvote/:id', :auth => [:can_vote] do
  quote = Quote.find(params[:id])
  user = User.find(session[:user_id])

  v = Vote.where :quote_id => quote.id, :user_id => user.id

  if v
    v.destroy
    quote.upvotes = quote.voters.size

    if request.xhr?
      status 200
      body(JSON.fast_generate({success: true}))
    else
      flash[:success] = 'Unvoted successfully!'
      redirect(request.params[:next] ? request.params[:next] : '/quotes/')
    end

  else
    if request.xhr?
      status 404
      body(JSON.fast_generate({success: false, err: "NOT_VOTED"}))
    else
      flash[:error] = 'You haven\'t voted on this!'
      redirect(request.params[:next] ? request.params[:next] : '/quotes/')
    end
  end
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
