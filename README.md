# qdb #

Quote Database Engine in Ruby / Sinatra.




## Running locally

**You need to have:** Postgres, Ruby ~1.9.1, `ruby-dev` (for a few modules) and
Bundler for the rubygem dependencies.

**TL;DR*** with Heroku Toolbelt:

    $ vim environment_variables
    $ cp environment_variables .env
    $ rake db:schema:load
    $ foreman start web 

**TL;DR** without Heroku Toolbelt:

    $ vim environment_variables
    $ cat environment_variables | sed "s/^/export /g" > env.sh
    $ source env.sh
    $ rake db:schema:load
    -- and then pick one from the following: --
    $ ruby qdb.rb 
    $ bundle exec rackup config.ru
    
### Environment variables

Before actually running the code, you should set up a few environment variables.
Check out the file `environment_variables` and assign values to everything.

The environment variables are:

**COOKIE_SECRET**: A unique password to sign your cookies with.  
**RECAPTCHA_SECRET**: [Google Recaptcha secret key][gr]  
**RECAPTCHA_CLIENTKEY**: [Google Recaptcha client/site key][gr]  
**DATABASE_URL**: Set this for Foreman/local running. This is the full database
URL that the app will use to connect to Postgres. Usually in the form of 
`postgres://[user]:[password]@localhost:[port]/`. Heroku will write the URL 
itself.

[gr]: https://www.google.com/recaptcha/admin

### Setting up the tables

Once you've got everything else setup, let Rake take care of creating the tables 
and setting up the indices for the app. 

    $ rake db:schema:load

It should run perfectly fine. If, on the other hand, you get some unpredictable error
about existing tables, then run the following command to drop the database containing
qdb tables:

    $ rake db:reset

After that, feel free to do `rake db:schema:load` to get your database in order.

### Actually Running

If you're using Heroku, copy-paste the file `environment_variables` into `.env`
which will then let you run the app locally using `foreman start web`.

Alternatively, set the same environment variables in a manner of your choosing
(for example, via `~/.bash_profile` or `export` commands) and run 
`bundle exec rackup config.ru` or `ruby qdb.rb`, whichever one you like more.



## Running on Heroku

Running this repo on Heroku is too easy.


### Preparing Heroku

First, start up by creating a Heroku app for this:

    $ heroku create

If you have an existing app, use this:

    $ heroku git:remote -a my-appname-1337


### Setting up the environment

Set up the environment variables named like in the file `environment_variables`.

The variables are described in an earlier section.

The next section describes how to push the code to Heroku. Make sure to pay very
close attention because it migth be a bit long-winded.


### Pushing the code

    $ git push heroku master

Don't forget to run a database schema load too:

    $ heroku run rake db:schema:load

(Note: every time you modify the database via a rake migration, you must `rake db:migrate` the remote end too!) 

And, after all this toil and trouble, your app is running on Heroku! Try the 
following command to open a browser with the app deployed.

    $ heroku open




## Dev environment

Here's a quick dev environment: run `vagrant up`. It will setup an Ubuntu 14.04
VM with the required packages, tools as well as the Heroku Toolbelt installed.




## Contributing

Send a pull request, yo




## Features

- User accounts with complex permissions
- Fancy Material layout (it even has ripples!)
- Fancy quote management
- Fancy user management
- Moderation logs
- Pagination
- TODO: Make everything configurable
- TODO: Different types of quote sorting
- TODO: Public moderation logs
- TODO: Voting on quotes




## Credit

(c) boxmein 2015, blah blah MIT license
