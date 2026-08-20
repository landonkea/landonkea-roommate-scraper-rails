# Handles every rental site that only shows its listings AFTER JavaScript
# runs on the page -- PadSplit, SpareRoom, Roomster, Cirtru,
# RoommateNation, and iRoomit. None of these expose clean server-rendered
# HTML we could parse with Nokogiri the way we do for Craigslist, so this
# class drives an actual headless Chrome browser (via the `ferrum` gem)
# to load the page, let its JavaScript run, scroll to trigger any
# lazy-loaded content, and then read back whatever ended up on screen.
# This is the Ruby stand-in for what Playwright + playwright-stealth did
# in the Python version. One important difference: Ferrum has no
# equivalent to playwright-stealth's anti-bot-detection tricks, so these
# sites may block us more often than they blocked the Python scraper --
# see the README for more on that trade-off.
module Scrapers
  class BrowserScraper
    # Every Arizona city the Python version checked across all of these
    # sites -- kept as one shared list since (unlike Craigslist's
    # per-region subdomains) these sites all take a city slug in the URL.
    AZ_CITIES = %w[
      phoenix tucson mesa chandler glendale scottsdale tempe peoria
      surprise flagstaff prescott sedona yuma lake-havasu-city
      sierra-vista show-low maricopa avondale goodyear buckeye
      casa-grande florence
    ].freeze

    # This snippet runs INSIDE the browser page (not in Ruby) via
    # `evaluate` below. It walks every `<a>` tag on the page, keeps only
    # links pointing at the target domain, and grabs the surrounding
    # card's visible text -- the same "no consistent markup, so read the
    # nearest container's plain text instead" heuristic the Python
    # version used, because these sites don't give us anything more
    # structured to select against. `%DOMAIN%` gets swapped for a real
    # domain before this ever reaches the browser.
    GENERIC_JS = <<~JS
      () => {
        const results = [];
        const seen = new Set();
        document.querySelectorAll('a').forEach(link => {
          const href = link.href;
          if (!href.includes('%DOMAIN%') || seen.has(href)) return;
          seen.add(href);
          const container = link.closest('li') || link.closest('article') || link.closest('div') || link;
          const text = (container.innerText || '').substring(0, 500);
          if (text.includes('$') && text.length > 20) {
            results.push({href, text});
          }
        });
        return results;
      }
    JS

    # PadSplit's own version of the same in-page script, hardcoded to its
    # listing-page URL pattern instead of a swappable domain (PadSplit's
    # listing links follow a distinct `/rooms-for-rent/listing/...` shape
    # that the generic domain check wouldn't reliably narrow down).
    PADSPLIT_JS = <<~JS
      () => {
        const results = [];
        const seen = new Set();
        document.querySelectorAll('a').forEach(link => {
          const href = link.href;
          if (!href.includes('padsplit.com/rooms-for-rent/listing') || seen.has(href)) return;
          seen.add(href);
          const container = link.closest('li') || link.closest('article') || link.closest('div') || link;
          const text = (container.innerText || '').substring(0, 500);
          if (text.includes('$') && text.length > 20) {
            results.push({href, text});
          }
        });
        return results;
      }
    JS

    # The five "generic" JS-rendered sites, each just needing a domain to
    # filter links by and a URL template with one `%s` for the city slug.
    # Every one of these uses the same modest scroll amount (3 scrolls of
    # 800px) since none of them lazy-load as aggressively as PadSplit does.
    SITES = [
      { name: "spareroom", domain: "spareroom.com", url_template: "https://www.spareroom.com/rooms-for-rent/%s_az", scroll_times: 3, scroll_pixels: 800 },
      { name: "roomster", domain: "roomster.com", url_template: "https://roomster.com/rooms-for-rent/%s-az", scroll_times: 3, scroll_pixels: 800 },
      { name: "cirtru", domain: "cirtru.com", url_template: "https://www.cirtru.com/rooms-for-rent/%s-az", scroll_times: 3, scroll_pixels: 800 },
      { name: "roommatenation", domain: "roommatenation.com", url_template: "https://roommatenation.com/us/az/%s", scroll_times: 3, scroll_pixels: 800 },
      { name: "iroomit", domain: "iroomit.com", url_template: "https://www.iroomit.com/rooms-for-rent/%s-az", scroll_times: 3, scroll_pixels: 800 }
    ].freeze

    # PadSplit gets its own site config (rather than sitting in the SITES
    # list above) because it needs three things none of the others do:
    # its own JS extraction script, a longer scroll (it lazy-loads more
    # aggressively), and an extra href filter to keep only genuine
    # Arizona listing links.
    PADSPLIT_SITE = {
      name: "padsplit",
      js: PADSPLIT_JS,
      url_template: "https://www.padsplit.com/rooms-for-rent/%s-az",
      scroll_times: 5,
      scroll_pixels: 1000,
      href_filter: ->(href) { href.to_s.include?("/az/") }
    }.freeze

    # `call_all` scrapes every generic site in SITES and returns the
    # total number of new listings saved across all of them.
    def self.call_all
      SITES.sum do |site|
        begin
          new(site).call
        rescue Ferrum::Error => e
          Rails.logger.warn("[BrowserScraper] #{site[:name]} failed: #{e.message}")
          0
        end
      end
    end

    # `call_padsplit` scrapes just PadSplit, kept separate since main.py
    # in the Python version called it out as its own distinct step too
    # (its own retry/error handling, its own log line).
    def self.call_padsplit
      new(PADSPLIT_SITE).call
    rescue Ferrum::Error => e
      Rails.logger.warn("[BrowserScraper] padsplit failed: #{e.message}")
      0
    end

    # `site` is one of the hashes above -- everything this instance needs
    # to know about which site it's scraping.
    def initialize(site)
      @site = site
    end

    # Runs one full browser session (start Chrome, visit every AZ city,
    # close Chrome) for this instance's site, and returns how many new
    # listings got saved.
    def call
      saved = 0
      # One headless Chrome instance per site, matching the Python
      # version's "one browser per site" approach -- reusing a single
      # browser across every city in the loop below is much faster than
      # starting a fresh Chrome process per city. `BROWSER_PATH` lets the
      # Docker image point Ferrum at Debian's `chromium` binary (see the
      # Dockerfile); left unset, Ferrum falls back to its own default
      # search for a local Chrome/Chromium install, which is fine for
      # running this on a normal development machine.
      browser = Ferrum::Browser.new(
        headless: true,
        timeout: 15,
        browser_path: ENV.fetch("BROWSER_PATH", nil)
      )
      begin
        AZ_CITIES.each do |city|
          saved += scrape_city(browser, city)
        end
      ensure
        # `ensure` guarantees Chrome actually gets shut down even if a
        # city scrape raises partway through -- without this, a crash
        # mid-run would leak a zombie Chrome process.
        browser.quit
      end
      saved
    end

    # Visits one city's listing page for this site, scrolls it, and pulls
    # out whatever the in-page JS finds. Kept separate from
    # `process_results` below so the "talk to a real browser" part and
    # the "make sense of what came back" part can be tested independently.
    def scrape_city(browser, city)
      url = format(@site[:url_template], city)

      begin
        # `wait_until: 'domcontentloaded'`-equivalent behavior in Ferrum
        # is just the default `go_to` -- Ferrum doesn't wait for every
        # last network request, only the initial page load, matching
        # Playwright's `domcontentloaded` option the Python version used.
        browser.go_to(url)
        # A short pause after load gives client-side JS time to render
        # listing cards before we start scrolling/reading -- same 2
        # second pause the Python version used.
        sleep 2
      rescue Ferrum::Error, Ferrum::TimeoutError
        # This one city's page failed to load -- move on to the next
        # city rather than aborting the whole site.
        return 0
      end

      begin
        # Scroll down repeatedly to trigger any lazy-loaded listing cards
        # -- how many times and how far is per-site (PadSplit needs more).
        (@site[:scroll_times] || 3).times do
          browser.execute("window.scrollBy(0, #{@site[:scroll_pixels] || 800})")
          sleep 0.3
        end
      rescue Ferrum::Error
        # Scrolling failing isn't fatal -- we can still try reading
        # whatever loaded before the scroll attempt.
      end

      raw_data = begin
        # Swap the real domain into the generic script (PadSplit already
        # has its final script baked into `@site[:js]`, so only the
        # generic sites need this substitution).
        js = @site[:js] || GENERIC_JS.sub("%DOMAIN%", @site[:domain])
        # `evaluate` runs the JS function in the browser and hands back
        # its return value, already converted into Ruby arrays/hashes.
        browser.evaluate("(#{js})()")
      rescue Ferrum::Error
        return 0
      end

      process_results(raw_data, city)
    end

    # Takes whatever the in-page JS handed back (an array of {href, text}
    # pairs) and turns it into saved Listing rows, applying the same
    # price/skip/score rules every other scraper uses. Pure Ruby, no
    # browser involved, so this is the part unit tests exercise directly.
    def process_results(raw_data, city)
      saved = 0

      Array(raw_data).each do |item|
        href = item["href"] || item[:href]

        # PadSplit's href_filter rejects anything that isn't a genuine
        # `/az/` listing link; the generic sites have no filter here, so
        # `@site[:href_filter]` being nil just means "keep everything."
        next if @site[:href_filter] && !@site[:href_filter].call(href)

        extracted = Scrapers::ListingExtractor.call(item["text"] || item[:text])
        next unless extracted

        price, title = extracted
        next unless price.between?(Listing::MIN_PRICE, Listing::MAX_PRICE)
        next if Listing.should_skip?(title)

        score = Listing.score_for(title, price)

        listing = Listing.find_or_create_by(source: @site[:name], source_id: href) do |l|
          l.title = title[0, 100]
          l.price = price
          l.url = href
          # These sites don't hand us a distinct neighborhood string the
          # way Craigslist does, so we use the city we were searching as
          # the location -- same fallback Python used.
          l.location = city
          l.posted_date = Date.current
          l.score = score
          l.first_seen_at = Time.current
        end

        if listing.previously_new_record?
          saved += 1
          DiscordNotifier.send_alert(listing) if listing.good?
        end
      end

      saved
    end
  end
end
