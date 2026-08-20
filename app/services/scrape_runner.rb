# The entry point that ties every scraper together, same job Python's
# main.py did. This is what the recurring background job (see
# app/jobs/scrape_listings_job.rb) actually calls.
#
# One behavior worth calling out explicitly: just like the Python
# version, this WIPES the entire listings table before every run (see
# `Listing.delete_all` below) rather than keeping a running history. That
# means every "good" listing found gets a fresh Discord alert every time
# the scraper runs, even if it also showed up yesterday -- this was a
# deliberate design in the original (a daily digest of what's currently
# available, not a "notify once ever" system), so this port keeps that
# behavior rather than quietly changing it.
class ScrapeRunner
  # `call` is the single method the job needs to invoke -- runs every
  # scraper in sequence and logs a short summary, mirroring the flow and
  # print statements of Python's `main()` function.
  def self.call
    Rails.logger.info("[ScrapeRunner] starting scrape at #{Time.current}")

    # Start every run from a clean slate -- matches Python's `clear_old`,
    # which deletes every row before scraping fresh. `delete_all` skips
    # instantiating each record (and callbacks) since we don't need
    # either for a full wipe -- just fast, direct deletion.
    Listing.delete_all

    # Craigslist first (fast, no browser needed), then the JS-heavy sites.
    craigslist_count = Scrapers::CraigslistScraper.call
    Rails.logger.info("[ScrapeRunner] craigslist: +#{craigslist_count} listings")

    browser_count = Scrapers::BrowserScraper.call_all
    Rails.logger.info("[ScrapeRunner] browser sites: +#{browser_count} listings")

    # PadSplit gets its own log line, same as the Python version broke it
    # out separately in main.py rather than lumping it in with the rest.
    padsplit_count = Scrapers::BrowserScraper.call_padsplit
    Rails.logger.info("[ScrapeRunner] padsplit: +#{padsplit_count} listings")

    total = Listing.in_price_range.count
    good = Listing.in_price_range.good.count
    Rails.logger.info("[ScrapeRunner] done - #{total} total, #{good} good (score >= #{Listing::MIN_SCORE})")

    # Returning a small summary hash makes this easy to inspect from the
    # Rails console or from a test, without needing to re-query the
    # database after calling this method.
    { craigslist: craigslist_count, browser_sites: browser_count, padsplit: padsplit_count, total: total, good: good }
  end
end
