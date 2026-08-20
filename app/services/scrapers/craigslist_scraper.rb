# Pulls room listings straight off Craigslist's search-results HTML.
# Craigslist's static server-rendered pages don't need a real browser to
# read -- a plain HTTP GET plus an HTML parser is enough, the same way
# Python's version used `requests` + BeautifulSoup instead of Playwright
# for this one site.
module Scrapers
  class CraigslistScraper
    # Every Arizona-area Craigslist subdomain the Python version checked --
    # kept as its own list (rather than one shared "cities" list) because
    # Craigslist splits the state into regional sites, unlike the other
    # rental sites which use one domain with a city in the URL path.
    REGIONS = %w[phoenix tucson flagstaff yuma prescott mohave showlow sierravista].freeze

    # A real desktop browser's User-Agent string -- sent with every
    # request because some sites (Craigslist included, historically)
    # reject or short-change requests that look like they're coming from
    # a bot with no User-Agent header at all.
    USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36".freeze

    # `call` runs the whole scrape -- every region, every listing on that
    # region's results page -- and returns however many NEW rows got
    # saved to the database. `class << self; ... end` below defines these
    # as class methods so callers just do `Scrapers::CraigslistScraper.call`.
    def self.call
      saved = 0
      # Loop over every AZ Craigslist region one at a time.
      REGIONS.each do |region|
        # Wrapping each region's work in its own begin/rescue means one
        # region timing out or returning bad HTML doesn't take down the
        # other seven -- matches the Python version's per-region `try/except`.
        begin
          saved += scrape_region(region)
        rescue Faraday::Error, Net::OpenTimeout => e
          Rails.logger.warn("[CraigslistScraper] #{region} failed: #{e.message}")
        end
      end
      saved
    end

    # Fetches and processes a single region's search-results page.
    def self.scrape_region(region)
      saved = 0
      # Craigslist's search URL takes min_price/max_price as query params
      # directly, so we let Craigslist itself do the first pass of price
      # filtering before we even parse the page.
      url = "https://#{region}.craigslist.org/search/roo?min_price=#{Listing::MIN_PRICE}&max_price=#{Listing::MAX_PRICE}"

      # `Faraday.get` performs the actual HTTP request; a 15-second
      # timeout keeps one slow region from stalling the whole scrape run.
      response = Faraday.get(url) do |req|
        req.headers["User-Agent"] = USER_AGENT
        req.options.timeout = 15
      end

      # Nokogiri::HTML turns the raw HTML string into a searchable
      # document tree -- this is the Ruby equivalent of
      # `BeautifulSoup(r.text, 'html.parser')`.
      doc = Nokogiri::HTML(response.body)

      # Craigslist marks every search result row with this CSS class --
      # `css` returns every matching element as an enumerable we can loop.
      doc.css("li.cl-static-search-result").each do |row|
        parsed = parse_row(row, region)
        # `parse_row` returns nil for rows it couldn't make sense of
        # (missing link or price) -- skip those instead of crashing.
        next unless parsed

        title, price, href, location = parsed

        # Titles matching the skip pattern (gender-restricted, weekly
        # rentals, etc.) are dropped entirely -- we don't even save them.
        next if Listing.should_skip?(title)

        score = Listing.score_for(title, price)

        # `find_or_create_by` is what makes re-running this scraper safe:
        # if a listing with this source+source_id already exists, it's
        # just returned as-is (no duplicate row); otherwise a fresh one
        # gets built and saved with everything from the `do` block below.
        listing = Listing.find_or_create_by(source: "craigslist", source_id: href) do |l|
          l.title = title[0, 100]
          l.price = price
          l.url = href
          l.location = location
          l.posted_date = Date.current
          l.score = score
          l.first_seen_at = Time.current
        end

        # `previously_new_record?` is true only on the call that actually
        # created the row -- exactly the "was this new?" signal Python
        # got back from `save_listing`'s `c.rowcount > 0` check.
        if listing.previously_new_record?
          saved += 1
          # Only bother alerting Discord for listings that cleared the
          # score bar -- matches Python's `if score >= 50: send_alert(...)`.
          DiscordNotifier.send_alert(listing) if listing.good?
        end
      end

      saved
    end

    # Pulls title/price/link/location out of one Craigslist result `<li>`.
    # Returns nil if the row doesn't have enough info to be useful.
    def self.parse_row(row, region)
      # Every result row should have at least one link -- if it doesn't,
      # there's nothing to point a Discord alert at, so skip it.
      link = row.at_css("a[href]")
      return nil unless link

      href = link["href"]
      # Some Craigslist links come back as full URLs already; others are
      # relative paths -- this makes sure we always end up with a
      # complete, clickable URL either way.
      href = "https://#{region}.craigslist.org#{href}" unless href.start_with?("http")

      # `.title` div holds the listing headline; if it's missing for some
      # reason, we fall back to an empty string rather than crashing.
      title = row.at_css("div.title")&.text&.strip || ""

      # `.price` div holds something like "$275" -- pull the digits back
      # out of it the same way ListingExtractor does elsewhere.
      price_text = row.at_css("div.price")&.text&.strip || ""
      price_match = price_text.match(/\$([\d,]+)/)
      return nil unless price_match

      price = price_match[1].delete(",").to_f

      # `.location` div is optional -- Craigslist doesn't always include
      # one, so we fall back to the region name itself as a reasonable
      # location string.
      location = row.at_css("div.location")&.text&.strip || region

      [ title, price, href, location ]
    end
  end
end
