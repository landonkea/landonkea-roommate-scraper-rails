require "test_helper"

# A thin test since the job itself is deliberately thin -- all it needs
# to prove is that running the job actually triggers ScrapeRunner (the
# class with all the real logic). The scraping/scoring behavior itself is
# covered by the scraper and model tests, not here.
class ScrapeListingsJobTest < ActiveJob::TestCase
  test "perform delegates to ScrapeRunner" do
    called = false
    ScrapeRunner.stub(:call, -> { called = true }) do
      ScrapeListingsJob.perform_now
    end

    assert called, "expected ScrapeListingsJob to call ScrapeRunner.call"
  end
end
