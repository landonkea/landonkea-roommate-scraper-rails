require "test_helper"

# These tests stub out Craigslist's HTML response with WebMock so we can
# check the scraper's parsing/filtering/saving logic without making a
# real network request. The fixture HTML below is a trimmed-down but
# structurally accurate stand-in for what craigslist.org actually
# returns for a room search.
class Scrapers::CraigslistScraperTest < ActiveSupport::TestCase
  # One page of fake Craigslist results: a good listing, a listing that
  # should be skipped entirely (weekly rate), and one with a relative
  # (not full) href, to prove the "make sure it's a full URL" logic works.
  SAMPLE_HTML = <<~HTML
    <html><body>
      <ul>
        <li class="cl-static-search-result">
          <a href="https://phoenix.craigslist.org/roo/private-room.html">
            <div class="title">Private furnished room near ASU</div>
            <div class="price">$275</div>
            <div class="location">Tempe</div>
          </a>
        </li>
        <li class="cl-static-search-result">
          <a href="https://phoenix.craigslist.org/roo/weekly-room.html">
            <div class="title">Room by the week, $90/wk</div>
            <div class="price">$90</div>
            <div class="location">Phoenix</div>
          </a>
        </li>
        <li class="cl-static-search-result">
          <a href="/roo/relative-room.html">
            <div class="title">Room available now</div>
            <div class="price">$260</div>
          </a>
        </li>
      </ul>
    </body></html>
  HTML

  setup do
    # Every region the scraper checks gets the same stubbed response --
    # simplest way to exercise the full REGIONS loop without eight
    # different fixtures.
    Scrapers::CraigslistScraper::REGIONS.each do |region|
      stub_request(:get, /#{region}\.craigslist\.org\/search\/roo/)
        .to_return(status: 200, body: SAMPLE_HTML, headers: { "Content-Type" => "text/html" })
    end
    # DiscordNotifier fires for every "good" listing found -- stubbed
    # here too so the scraper test doesn't also depend on Discord's API.
    stub_request(:post, /discord.com\/api\/webhooks/).to_return(status: 204)
  end

  test "saves a good listing with the right fields" do
    Scrapers::CraigslistScraper.call

    listing = Listing.find_by(source: "craigslist", source_id: "https://phoenix.craigslist.org/roo/private-room.html")
    assert listing.present?
    assert_equal "Private furnished room near ASU", listing.title
    assert_equal 275.0, listing.price
    assert_equal "Tempe", listing.location
    assert_equal Listing.score_for("Private furnished room near ASU", 275.0), listing.score
  end

  test "skips listings matching the skip pattern entirely" do
    Scrapers::CraigslistScraper.call

    assert_nil Listing.find_by(source_id: "https://phoenix.craigslist.org/roo/weekly-room.html")
  end

  test "turns a relative href into a full URL using the region domain" do
    Scrapers::CraigslistScraper.call

    listing = Listing.find_by(title: "Room available now")
    assert_equal "https://phoenix.craigslist.org/roo/relative-room.html", listing.url
  end

  test "falls back to the region name when a row has no location div" do
    Scrapers::CraigslistScraper.call

    listing = Listing.find_by(title: "Room available now")
    assert_equal "phoenix", listing.location
  end

  test "running the scraper twice does not create duplicate rows" do
    Scrapers::CraigslistScraper.call
    first_count = Listing.count

    Scrapers::CraigslistScraper.call
    assert_equal first_count, Listing.count
  end

  test "does not blow up when a region's request fails" do
    Scrapers::CraigslistScraper::REGIONS.each do |region|
      stub_request(:get, /#{region}\.craigslist\.org\/search\/roo/).to_timeout
    end

    assert_nothing_raised { Scrapers::CraigslistScraper.call }
  end
end
