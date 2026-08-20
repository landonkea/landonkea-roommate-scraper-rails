require "test_helper"

# ListingExtractor is the piece that turns a messy blob of a listing
# card's plain text into a usable (price, title) pair -- these tests feed
# it text shaped the way a real JS-rendered site's card would look once
# `innerText` flattens it, without needing an actual browser running.
class Scrapers::ListingExtractorTest < ActiveSupport::TestCase
  test "pulls the price and the first long non-price line as the title" do
    text = "Private room near ASU\n$275/month\nAvailable now\nContact for details"

    price, title = Scrapers::ListingExtractor.call(text)

    assert_equal 275.0, price
    assert_equal "Private room near ASU", title
  end

  test "strips commas out of four-digit prices" do
    text = "Furnished master suite\n$1,200/month"

    price, _title = Scrapers::ListingExtractor.call(text)

    assert_equal 1200.0, price
  end

  test "returns nil when there's no dollar amount anywhere in the text" do
    assert_nil Scrapers::ListingExtractor.call("Just some text with no price at all here")
  end

  test "falls back to the first line when no line qualifies as a title" do
    # Every line here is either too short or contains a dollar sign, so
    # none of them pass the "long line with no $" title heuristic.
    text = "$300\n$50 fee"

    _price, title = Scrapers::ListingExtractor.call(text)

    assert_equal "$300", title
  end

  test "ignores blank lines when hunting for a title" do
    text = "\n\n   \n$275\n\nCozy private room close to downtown\n"

    _price, title = Scrapers::ListingExtractor.call(text)

    assert_equal "Cozy private room close to downtown", title
  end
end
