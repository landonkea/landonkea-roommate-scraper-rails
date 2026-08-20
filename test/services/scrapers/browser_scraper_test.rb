require "test_helper"

# BrowserScraper#process_results is the part of the JS-site scraper that
# doesn't actually need a real Chrome browser -- it just takes whatever
# the in-page JavaScript would have returned (an array of {href, text}
# pairs) and turns that into saved Listing rows. Testing it directly like
# this means these tests run fast and don't depend on Chrome being
# installed on whatever machine runs the test suite (including CI).
class Scrapers::BrowserScraperTest < ActiveSupport::TestCase
  setup do
    stub_request(:post, /discord.com\/api\/webhooks/).to_return(status: 204)
  end

  test "saves an in-range, non-skipped listing from a generic site" do
    site = Scrapers::BrowserScraper::SITES.find { |s| s[:name] == "spareroom" }
    scraper = Scrapers::BrowserScraper.new(site)

    raw_data = [
      { "href" => "https://www.spareroom.com/rooms-for-rent/listing/1", "text" => "Private furnished room\n$275/month\nAvailable now" }
    ]

    saved = scraper.process_results(raw_data, "phoenix")

    assert_equal 1, saved
    listing = Listing.find_by(source: "spareroom", source_id: "https://www.spareroom.com/rooms-for-rent/listing/1")
    assert_equal 275.0, listing.price
    assert_equal "phoenix", listing.location
  end

  test "drops listings priced outside the MIN_PRICE..MAX_PRICE window" do
    site = Scrapers::BrowserScraper::SITES.find { |s| s[:name] == "spareroom" }
    scraper = Scrapers::BrowserScraper.new(site)

    raw_data = [
      { "href" => "https://www.spareroom.com/rooms-for-rent/listing/2", "text" => "Nice room\n$900/month" }
    ]

    saved = scraper.process_results(raw_data, "phoenix")

    assert_equal 0, saved
    assert_nil Listing.find_by(source_id: "https://www.spareroom.com/rooms-for-rent/listing/2")
  end

  test "drops listings matching the skip pattern" do
    site = Scrapers::BrowserScraper::SITES.find { |s| s[:name] == "spareroom" }
    scraper = Scrapers::BrowserScraper.new(site)

    raw_data = [
      { "href" => "https://www.spareroom.com/rooms-for-rent/listing/3", "text" => "Ladies only room\n$250/month" }
    ]

    saved = scraper.process_results(raw_data, "phoenix")

    assert_equal 0, saved
  end

  test "PadSplit's href_filter rejects links that aren't real /az/ listings" do
    scraper = Scrapers::BrowserScraper.new(Scrapers::BrowserScraper::PADSPLIT_SITE)

    raw_data = [
      { "href" => "https://www.padsplit.com/some-other-page", "text" => "Private room\n$275/month" },
      { "href" => "https://www.padsplit.com/rooms-for-rent/listing/az/4", "text" => "Private room\n$275/month" }
    ]

    saved = scraper.process_results(raw_data, "phoenix")

    assert_equal 1, saved
    assert_nil Listing.find_by(source_id: "https://www.padsplit.com/some-other-page")
    assert Listing.find_by(source_id: "https://www.padsplit.com/rooms-for-rent/listing/az/4").present?
  end

  test "running process_results twice with the same href does not duplicate the row" do
    site = Scrapers::BrowserScraper::SITES.find { |s| s[:name] == "spareroom" }
    scraper = Scrapers::BrowserScraper.new(site)

    raw_data = [
      { "href" => "https://www.spareroom.com/rooms-for-rent/listing/5", "text" => "Private room\n$275/month" }
    ]

    scraper.process_results(raw_data, "phoenix")
    second_saved = scraper.process_results(raw_data, "phoenix")

    assert_equal 0, second_saved
    assert_equal 1, Listing.where(source: "spareroom", source_id: "https://www.spareroom.com/rooms-for-rent/listing/5").count
  end
end
