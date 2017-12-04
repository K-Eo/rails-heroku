def ruby_version
  ruby_run = `ruby -v`
  ruby_run.to_s.match(/\Aruby ([0-9]+\.[0-9]+\.[0-9]+)/)[1]
end

def secrets
  gsub_file 'config/secrets.yml',
            /secret_key_base:\s[0-9a-f]{128}/,
            'secret_key_base: <%= ENV["SECRET_KEY_BASE"] %>'
end

def development_environment
  application nil, env: 'development' do
    "config.action_mailer.default_url_options = { host: 'localhost', port: 3000 }"
  end
end

def test_environment
  application nil, env: 'test' do
    "config.action_mailer.default_url_options = { host: 'localhost', port: 3000 }"
  end
end

def production_environment
  # Get app name for Heroku review apps
  inject_into_file 'config/environments/production.rb',
                   "app_name = ENV['HEROKU_APP_NAME'] || '#{@app_name}'\n\n",
                   before: 'Rails.application.configure do'

  # Force ssl
  gsub_file 'config/environments/production.rb',
            /# config.force_ssl = true/,
            'config.force_ssl = true'

  # Use sidekiq
  gsub_file 'config/environments/production.rb',
            /# config.active_job.queue_adapter     = :resque/,
            'config.active_job.queue_adapter     = :sidekiq'

  # Add cache-control for public files.
  # Configure mail with Heroku
  application nil, env: 'production' do
  %{
    # Cache public files
    config.public_file_server.headers = {
      'Cache-Control' => 'public, max-age=31536000'
    }

    config.action_mailer.default_url_options = { host: "\#{app_name}.herokuapp.com" }

    # Sendgrid Heroku config
    config.action_mailer.delivery_method = :smtp
    config.action_mailer.perform_deliveries = true

    config.action_mailer.smtp_settings = {
      :user_name => ENV['SENDGRID_USERNAME'],
      :password => ENV['SENDGRID_PASSWORD'],
      :domain => "https://\#{app_name}.herokuapp.com",
      :address => 'smtp.sendgrid.net',
      :port => 587,
      :authentication => :plain,
      :enable_starttls_auto => true
    }
  }
  end
end

def gem_config
  # Add ruby version for Heroku
  inject_into_file 'Gemfile', "\n\nruby '#{@ruby_version}'", after: "source 'https://rubygems.org'"

  # Add additional gems
  inject_into_file 'Gemfile', after: "# gem 'capistrano-rails', group: :development\n" do
    %{
  gem 'devise'
  gem 'sidekiq'
  gem 'slim-rails'
  gem 'rails-i18n'
  gem 'kaminari'
  gem 'webpacker'
    }
  end

  # Add development gems
  inject_into_file 'Gemfile', after: "gem 'selenium-webdriver'" do
    %{
  gem "dotenv-rails"
  gem "rubocop", require: false
  gem "pry-byebug"
  gem "guard", require: false
  gem "guard-spinach", require: false
  gem "guard-rspec", require: false
  gem "rspec-rails"
  gem "factory_bot_rails"
  gem "spinach-rails"
  gem "database_cleaner"
  gem "capybara-screenshot"
  gem "rails-controller-testing"}
  end
end

def config_environment
  inject_into_file 'config/environment.rb', after: 'Rails.application.initialize!' do
    <<~RUBY
      \n
      ActionView::Base.field_error_proc = Proc.new do |html_tag, instance|
        html_tag.html_safe
      end
    RUBY
  end
end

def env_config
  template ".env.example", ".env.example"
  template ".env", ".env"

  gsub_file ".env",
            "SECRET_KEY_BASE_PLACEHOLDER",
            `rails secret`

  gsub_file ".env",
            "DB_HOST_PLACEHOLDER",
            'localhost'

  gsub_file ".env",
            "USER_PLACEHOLDER",
            'postgres'

  gsub_file ".env",
            "PASSWORD_PLACEHOLDER",
            'postgres'

  gsub_file ".env",
            /^\n/,
            ''
end

def templates_config
  inside('config') do
    run "rm puma.rb"
  end

  template "puma.rb", "config/puma.rb"
  template "Procfile.tt", "Procfile"
  template "app.json.tt", "app.json"
  template "sidekiq.yml.tt", "config/sidekiq.yml"

  gsub_file "app.json",
            "APP_NAME",
            @app_name
end

def devise
  run "bundle install"
  generate "devise:install"
  model_name = ask("What would you like the user model to be called? [user]")
  model_name = "user" if model_name.blank?
  generate "devise", model_name
end

def rspec
  generate "rspec:install"
end

source_paths.unshift(File.join(Dir.pwd, '../'))
@ruby_version = ruby_version

gem_config
# secrets
# development_environment
# test_environment
# production_environment
templates_config
# env_config
# config_environment
# devise
