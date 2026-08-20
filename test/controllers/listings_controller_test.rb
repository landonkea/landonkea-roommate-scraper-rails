require "test_helper"

# These are integration tests for the dashboard page -- they hit the
# route the way a real browser would (an HTTP GET) and check what comes
# back, using the three fixture listings in test/fixtures/listings.yml
# (one great, one mediocre, one overpriced) to verify sorting and
# filtering actually work end to end.
class ListingsControllerTest < ActionDispatch::IntegrationTest
  test "root path renders the dashboard successfully" do
    get root_url
    assert_response :success
  end

  test "index shows every listing sorted best-score-first" do
    get listings_url

    assert_response :success
    # The great_room fixture (score 90) should appear before the
    # mediocre_room fixture (score 0) in the raw HTML response body.
    assert_operator response.body.index(listings(:great_room).title),
      :<, response.body.index(listings(:mediocre_room).title)
  end

  test "filtering by source only shows listings from that source" do
    get listings_url, params: { source: "padsplit" }

    assert_response :success
    assert_match listings(:mediocre_room).title, response.body
    assert_no_match(/#{Regexp.escape(listings(:great_room).title)}/, response.body)
  end

  test "the good-only filter hides low-scoring listings" do
    get listings_url, params: { good: "1" }

    assert_response :success
    assert_match listings(:great_room).title, response.body
    assert_no_match(/#{Regexp.escape(listings(:mediocre_room).title)}/, response.body)
  end

  test "shows a friendly empty state when filters match nothing" do
    get listings_url, params: { source: "does-not-exist" }

    assert_response :success
    assert_match "No listings yet", response.body
  end
end
