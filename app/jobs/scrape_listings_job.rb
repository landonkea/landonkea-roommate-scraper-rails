# A background job is work that runs outside the normal request/response
# cycle -- instead of a website visitor waiting 5+ minutes for a scrape to
# finish, Solid Queue (Rails 8's built-in job backend, already wired up
# by `rails new`) runs this on its own schedule and the dashboard just
# reads whatever's in the database whenever someone loads it.
class ScrapeListingsJob < ApplicationJob
  # `:default` puts this job on Solid Queue's default work queue -- fine
  # here since this app only has the one kind of background job.
  queue_as :default

  # `perform` is the method Solid Queue actually calls when it's time to
  # run this job -- all the real work lives in ScrapeRunner so it stays
  # easy to trigger manually from the Rails console too, not just from a
  # scheduled job.
  def perform(*args)
    ScrapeRunner.call
  end
end
