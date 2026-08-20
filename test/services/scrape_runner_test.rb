require "test_helper"

# ScrapeRunner just orchestrates the individual scrapers -- their own
# behavior is covered in test/services/scrapers/*_test.rb, so this test
# only needs to prove ScrapeRunner wires them together correctly: wipes
# old data first, calls all three scrapers, and reports a sane summary.
class ScrapeRunnerTest < ActiveSupport::TestCase
  test "clears old listings before scraping and returns a summary" do
    # A leftover listing from a previous run -- should be gone by the
    # time ScrapeRunner finishes, since it wipes the table up front.
    Listing.create!(source: "craigslist", source_id: "stale", price: 250, first_seen_at: 1.day.ago)

    Scrapers::CraigslistScraper.stub(:call, 2) do
      Scrapers::BrowserScraper.stub(:call_all, 3) do
        Scrapers::BrowserScraper.stub(:call_padsplit, 1) do
          summary = ScrapeRunner.call

          assert_equal({ craigslist: 2, browser_sites: 3, padsplit: 1, total: 0, good: 0 }, summary)
        end
      end
    end

    assert_nil Listing.find_by(source_id: "stale")
  end
end
