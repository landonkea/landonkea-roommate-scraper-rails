source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.4"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use sqlite3 as the database for Active Record
gem "sqlite3", ">= 2.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"
# Use Tailwind CSS [https://github.com/rails/tailwindcss-rails]
gem "tailwindcss-rails"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
gem "image_processing", "~> 1.2"

# Nokogiri parses the raw HTML we pull down from Craigslist so we can dig
# through it for listing titles, prices, and links -- same job BeautifulSoup
# did in the Python version, just the Ruby equivalent.
gem "nokogiri"
# Faraday is the HTTP client our scraper uses to actually fetch each page
# (send the request, get HTML back) before Nokogiri parses it.
gem "faraday"
# Ferrum drives a real headless Chrome browser for the handful of sites
# (PadSplit, SpareRoom, etc.) that only show their listings after
# JavaScript runs -- this is the Ruby stand-in for Playwright, which the
# Python version used for the exact same reason.
gem "ferrum"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"

  # Loads variables out of a local .env file into ENV automatically when
  # the app boots in development -- this is what lets DISCORD_WEBHOOK_URL
  # in .env actually reach ENV["DISCORD_WEBHOOK_URL"] without needing to
  # export it by hand in every terminal session. Only needed here (not in
  # production), since a real deployment sets ENV vars through its
  # hosting platform instead of a .env file.
  gem "dotenv-rails"
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem "selenium-webdriver"

  # WebMock intercepts any real HTTP request our tests would otherwise
  # send out (Faraday calls to Craigslist or Discord, for instance) and
  # lets us stub a fake response instead -- keeps the test suite fast,
  # deterministic, and safe to run with no internet connection at all.
  gem "webmock"

  # Minitest 6 split its `stub` helper (swap out a method for one test,
  # like faking ENV.fetch or ScrapeRunner.call) into its own gem instead
  # of bundling it by default -- this pulls that piece back in.
  gem "minitest-mock"
end
