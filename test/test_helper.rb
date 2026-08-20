ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
# WebMock replaces Ruby's real networking with a fake, in-process stand-in
# for the whole test run -- pulled in here so every test file that needs
# it (the scraper tests, the Discord notifier test) can just use it
# without each one having to `require` it separately.
require "webmock/minitest"
# Pulls in Minitest's `stub` helper (used to temporarily swap out a
# method on any object, like ENV.fetch or ScrapeRunner.call, for the
# duration of a single test) -- not loaded by `rails/test_help` on its own.
require "minitest/mock"

# This is the safety net that makes WebMock actually useful: it makes ANY
# HTTP request a test forgets to stub raise an error instead of silently
# reaching out to the real internet. Without this, a bug in a test could
# quietly hit the real Craigslist or Discord and nobody would notice.
WebMock.disable_net_connect!(allow_localhost: true)

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
