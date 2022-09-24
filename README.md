# qdb #

Quote Database written in Ruby / Sinatra.

## Features

- User accounts with complex permissions
- Fancy Material layout (it even has ripples!)
- Fancy quote management
- Fancy user management
- Moderation logs
- Pagination
- Voting on quotes
- Web App Security (TM)
- TODO: Dynamic reloading and stuff
- TODO: decent stylesheets and class tags for configurable themes
- TODO: Make everything configurable
- Different types of quote sorting
- TODO: Public moderation logs

## Running locally

**You need to have:** a PostgreSQL server, Ruby 2.4, `ruby-dev` (to be able to install a few modules) and
Bundler for the rubygem dependencies.1


**TL;DR**:

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
`postgres://[user]:[password]@localhost:[port]/[database]`. Heroku will write the URL 
itself.

[gr]: https://www.google.com/recaptcha/admin

### Setting up the tables

Before you can run Rake, you have to tell PostgreSQL about the database account
and database you'll be using.

Log into psql, create a user, set its password (usually via psql), and then give
it a new database. Then, make sure your `config/database.yml` matches your 
PostgreSQL config, that the URL in `.env` / `environment_variables` / `env.sh` 
matches the postgresql config, and then you're done. 


Once you've got everything else setup, let Rake take care of creating the tables 
and setting up the indices for the app. 

    $ rake db:schema:load

It should now run fine.

If you get an error with there not being a `development` config, but there is an
option for `default_env`, then run rake again with `RACK_ENV=default_env`.

If you get authentication errors, make sure your PSQL usernames and passwords are 
correct everywhere and that the authentication method you set up is correct.

If the tables it needs to generate exist already, then run the following command
to drop the database containing qdb tables:

    $ rake db:reset

After that, feel free to do `rake db:schema:load` to get your database in order.

### Actually Running

1. Define the above env variables
2. Run `ruby qdb.rb`

## Dev environment

Here's a quick dev environment: run `vagrant up`. It will setup an Ubuntu 14.04
VM with the required packages.

## Contributing

Send a pull request, yo

## Credit

(c) boxmein 2015, blah blah MIT license
