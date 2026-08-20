require "test_helper"

# These tests cover the two things Listing is really responsible for
# beyond plain database storage: the scoring math (Listing.score_for) and
# the skip-entirely filter (Listing.should_skip?), both ported straight
# from Python's filters.py. Getting these right matters more than almost
# anything else in the app, since they're what decides which listings a
# person actually gets alerted about.
class ListingTest < ActiveSupport::TestCase
  test "should_skip? is true for gender-restricted titles" do
    assert Listing.should_skip?("Room for rent, ladies only")
    assert Listing.should_skip?("Looking for female roommate")
  end

  test "should_skip? is true for weekly-rate titles" do
    assert Listing.should_skip?("Room available $80/wk")
    assert Listing.should_skip?("Sober living house, weekly rates")
  end

  test "should_skip? is false for an ordinary monthly listing" do
    assert_not Listing.should_skip?("Private furnished room near ASU")
  end

  test "score_for returns zero for bad-word titles regardless of price" do
    assert_equal 0, Listing.score_for("Shared room with couch in living room", 250)
  end

  test "score_for gives the sweet-spot price range the biggest boost" do
    # A plain title with no good/bad keywords, priced right in the
    # 220-300 sweet spot, should land at the baseline (50) plus the
    # sweet-spot bonus (15) = 65.
    assert_equal 65, Listing.score_for("Room available now", 250)
  end

  test "score_for gives a smaller boost outside the sweet spot but within range" do
    # Same plain title, but priced at 340 -- inside 200-350 overall, but
    # outside the 220-300 sweet spot, so it only earns the smaller +5.
    assert_equal 55, Listing.score_for("Room available now", 340)
  end

  test "score_for penalizes prices above the max" do
    # Above 350 loses 10 points instead of gaining any price bonus:
    # 50 - 10 = 40.
    assert_equal 40, Listing.score_for("Room available now", 400)
  end

  test "score_for stacks good-word, private, and price bonuses" do
    # "private" appears in both GOOD_WORDS (+20) and the standalone
    # "private" check (+15); the price is in the sweet spot (+15).
    # 50 + 20 + 15 + 15 = 100, then clamped to the 0-100 range (already
    # exactly at the ceiling here).
    assert_equal 100, Listing.score_for("Private furnished room near ASU", 275)
  end

  test "score_for's only price penalty is -10, so a plain overpriced title still lands above zero" do
    # 50 baseline - 10 overpriced penalty, no other bonuses apply here --
    # confirms the penalty is exactly -10 and doesn't stack or compound.
    assert_equal 40, Listing.score_for("Room available, no other details", 900)
  end

  test "good? is true only at or above the alert threshold" do
    listing = listings(:great_room)
    assert listing.good?

    listing = listings(:mediocre_room)
    assert_not listing.good?
  end

  test "in_price_range scope excludes listings outside MIN_PRICE..MAX_PRICE" do
    in_range = Listing.in_price_range
    assert_includes in_range, listings(:great_room)
    assert_not_includes in_range, listings(:overpriced_room)
  end

  test "best_first scope sorts by score descending" do
    ordered = Listing.best_first.to_a
    assert_equal listings(:great_room), ordered.first
  end

  test "a listing needs a source, source_id, and price to be valid" do
    listing = Listing.new
    assert_not listing.valid?
    assert_includes listing.errors.attribute_names, :source
    assert_includes listing.errors.attribute_names, :source_id
    assert_includes listing.errors.attribute_names, :price
  end

  test "the unique index on source+source_id prevents duplicate rows" do
    duplicate = Listing.new(
      source: listings(:great_room).source,
      source_id: listings(:great_room).source_id,
      price: 275,
      first_seen_at: Time.current
    )
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save!(validate: false) }
  end
end
