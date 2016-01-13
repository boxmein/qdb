require 'sinatra'
require 'sinatra/activerecord'
require './config/env'
require 'will_paginate'
require 'will_paginate/active_record'
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

$DEBUG = !!ENV['DEBUG']

puts "-- qdb -- starting on #{Time.now}"
puts "setting up Rack modules" if $DEBUG
abort "Set $COOKIE_SECRET to a cookie secret!" unless ENV['COOKIE_SECRET']

use Rack::Session::EncryptedCookie, :expire_after => 604800,
                                    :secret => ENV['COOKIE_SECRET'],
                                    :http_only => true
use Rack::Csrf, :alert => true, :skip => ['POST:/upvote/\\d+']
use Rack::Flash, :accessorize => [:info, :success, :error]

abort "Set $RECAPTCHA_CLIENTKEY to your recaptcha public/client key!" unless ENV['RECAPTCHA_CLIENTKEY']
abort "Set $RECAPTCHA_SECRET to your recaptcha secret!" unless ENV['RECAPTCHA_SECRET']
Sinatra::ReCaptcha.public_key = ENV['RECAPTCHA_CLIENTKEY']
Sinatra::ReCaptcha.private_key = ENV['RECAPTCHA_SECRET']

puts "Recaptcha initialized with public key #{ENV['RECAPTCHA_CLIENTKEY']} and private key #{ENV['RECAPTCHA_SECRET']}." if $DEBUG

puts "configuring everything else..." if $DEBUG
configure do
  set :port, ENV['PORT'] || 5000
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
      # puts "authenticating for #{session[:username]}" if $DEBUG
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
      # print "user #{session[:username]} flags #{session[:flags]} has required role: " if $DEBUG
      roles.each do |role|
        # skip the :logged_in role
        next if role == :logged_in
        flag_exists = (curr_flags & auth_flags[role]) != 0
        # print "#{role} " if flag_exists && $DEBUG
        allowed = allowed && flag_exists
      end
      # puts "" if $DEBUG

      unless allowed
        # puts "User #{session[:username]} flags #{session[:flags]} denied access to #{request.request_method} #{request.path_info}" if $DEBUG
        if request.xhr?
          status 401
          body(JSON.fast_generate({success: false, err: 'UNAUTHORIZED'}))
        else
          flash[:error] = 'You aren\'t allowed to go here! :('
          redirect '/'
        end
      end
      # puts "User #{session[:username]} flags #{session[:flags]} was allowed access to #{request.request_method} #{request.path_info}" if $DEBUG
      p request
    end
  end

  # Mod logs are now also stdout
  def logModAction(name, action, on)
    puts "modaction! name=#{name} action=#{action} on=#{on}"
  end

  set :logModAction, lambda { |name, act, on| logModAction(name, act, on) }
  set :public_folder, File.dirname(__FILE__) + '/static'
  set :recaptcha_secret, ENV['RECAPTCHA_SECRET']
end

before do
  if session[:username] != nil
    @loggedIn = true
    @username = session[:username]
    @flags    = session[:flags]
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
  @pageTitle = "error doing some stuff"
  erb :error, locals: {message: env['sinatra.error'].message}
end

error 403 do
  @pageTitle = "you don't seem to be authorized"
  erb :'responses/403'
end

not_found do
  @pageTitle = "sick surfing, dude! you're way off course though..."
  erb :'responses/404'
end

#
# Viewing quotes
#

get '/' do
  @pageTitle = "splash page"
  erb :index
end


# Get which quote?
get '/quote/:id' do
  pass if params[:id] == 'new'
  redirect '/quotes' if params[:id] == 'list'

  puts "Looking for quote #{:id}..."
  @quote = Quote.where(:id => params[:id].to_i).first

  if @loggedIn
    user = User.where(name: session[:username]).first
    @voted = Vote.where(quote: @quote, user: user).first != nil
  else
    @voted = false
  end

  @isQuotePage = true

  if (@quote && @quote.approved) or
     (@quote && @loggedIn && @userFlags.include?(:approve_quotes))
    @pageTitle = "quote ##{@quote.id} by #{@quote.author}"
    erb :'quote/quote_view'
  else
    flash[:error] = 'There is no quote with this ID!'
    redirect '/quotes/'
  end

end

# Get a list of ~40 quotes
get '/quotes/:sort_by' do
  possible_orders = {
    :voted => 'upvotes DESC',
    :new => 'id DESC',
    :old => 'id ASC'
  }

  page = params[:page] == 0 ? 1 : params[:page]

  where_hash = {:approved => true}
  @pageTitle = "quotes - page #{params[:page]}"

  # Get all quotes by a specific user, show unapproved quotes too if author listing
  if params[:by]
    params[:by] = session[:username] if params[:by] == 'me'
    @user = User.where(name: params[:by]).first
    if @user 
      where_hash[:author] = @user.name
      if @loggedIn and session[:username] == params[:by]
        where_hash.delete :approved
      end
      @pageTitle = "quotes by #{@user.name} - page #{params[:page]}"
    else
      flash[:error] = 'There is no such user!'
    end
  end

  if params[:sort_by]
    sort_by = params[:sort_by].to_sym

    if possible_orders.include? sort_by
      sort_by = possible_orders[sort_by]
    else
      sort_by = possible_orders[:old]
    end
  end

  puts "Received #{params[:sort_by].inspect}, sorting by #{sort_by.inspect}!" if $DEBUG

  @quotes = Quote.where(where_hash).order(sort_by).page(params[:page])

  if @loggedIn
    user = User.where(name: session[:username]).first
    @loggedInUser = user.name
    @votedQuotes = Vote.where(user: user).to_a.map(&:quote_id)
  end

  erb :'quote/list'
end

get '/quote' do
  redirect '/quotes/old'
end

get '/quotes' do
  redirect '/quotes/old'
end

get '/quotes/' do 
  redirect '/quotes/old'
end

#
# Logins
#


get '/user/login' do
  @pageTitle = "login"
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
    puts "didn't receive entire font! login failed for username #{params[:name]}" if $DEBUG
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
  @pageTitle = "register"
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

  # Unprivileged users can post quotes to the queue and vote automatically.
  # CAPTCHA and low publicity keeps bots away :D
  params[:user][:flags] = settings.auth_flags[:post_quotes] | settings.auth_flags[:can_vote]
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
    @pageTitle = "error registering - try again!"
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
  @pageTitle = "your settings"
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
  @pageTitle = "change your password"
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
  @pageTitle = "delete your account from this site"
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
    @pageTitle = "editing user #{@user.name}"
    erb :'user/edit'
  else
    404
  end
end

post '/user/:id/edit', :auth => [:edit_users] do
  #puts "am now in user/edit" if $DEBUG
  @user = User.find(params[:id])
  if @user
    #puts "found a user" if $DEBUG
    u = params[:user]
    @user.id = u[:id]
    @user.name = esc u[:name]
    @user.password = u[:password]

    if @user.save
      logModAction session[:username], ":edit_users/save", "#{@user.name} edit success"
      flash[:success] = 'Successfully edited the user!'
      redirect(request.params[:next] ? request.params[:next] : '/user/list')
    else
      logModAction session[:username], ":edit_users/save", "#{@user.name} edit save error"
      flash[:error] = 'Error saving the user!'
      redirect request.path_info
    end
  
  else
    logModAction session[:username], ":edit_users/save", "#{@user.name} edit fail"
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
  @pageTitle = "add new quote"
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
    flash[:success] = 'Successfully submitted and waiting to be approved!'
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
    @pageTitle = "edit quote"
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
    @pageTitle = "delete quote #{params[:id]}"
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
  @pageTitle = "list of users"
  erb :'user/list'
end

get '/user/:id/set_flags', :auth => [:set_flags] do
  @id = params[:id]
  user = User.find(params[:id])
  @username = user.name
  @userflags = user.flags
  @pageTitle = "set the user flags for user #{@username}"
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
  @pageTitle = "moderator approval queue"
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
        $stderr.puts "warn: failed to update upvote count, but vote object still remains!" if $DEBUG
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
