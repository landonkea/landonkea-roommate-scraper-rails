# This is the ActiveRecord model for a single room/roommate listing --
# ActiveRecord is Rails' way of turning a database table (`listings`, from
# the migration next to this file) into a plain Ruby class you can query
# and manipulate with regular method calls instead of writing raw SQL.
# It also carries the scoring and filtering logic that used to live in the
# Python project's filters.py, so it's the single place that decides
# whether a listing is any good.
class Listing < ApplicationRecord
  # The lowest monthly rent we're willing to consider. Mirrors Python's
  # `MIN_PRICE = 200` in config.py exactly.
  MIN_PRICE = 200
  # The highest monthly rent we're willing to consider. Mirrors Python's
  # `MAX_PRICE = 350` in config.py exactly.
  MAX_PRICE = 350
  # A listing needs at least this score before we bother pinging Discord
  # about it -- matches Python's `MIN_SCORE = 50`.
  MIN_SCORE = 50

  # Titles matching any of these words mean "skip this listing entirely,
  # don't even save it" -- gender-restricted rooms, weekly/short-term
  # rentals, sober-living homes, etc. This is a straight port of Python's
  # `SKIP_PATTERN` regex from filters.py, kept case-insensitive the same way.
  SKIP_PATTERN = /ladies|female|women|men'?s|sober|weekly|\/wk|\/week|per week|a week|by the week|for \d+ week|weeks|month to month|\d+\/wk|\d+ a week/i

  # Titles matching any of these words are real listings we still save, but
  # they score a flat zero -- shared spaces, couches, RVs, chores-for-rent
  # arrangements, and so on. Ported from Python's `BAD_WORDS`.
  BAD_WORDS = /shared|living room|futon|couch|trailer|rv |rv\)|parking|sober|homestay|hostel|airbnb|help:|errands|cleaning|general help|backyard/i

  # Titles matching any of these words get a score boost -- private rooms,
  # furnished units, good neighborhoods, walkability, etc. Ported from
  # Python's `GOOD_WORDS`.
  GOOD_WORDS = /private|furnished|utilities included|pool|asu|downtown|tempe|scottsdale|chandler|gilbert|walking distance/i

  # Every listing needs to know which site it came from and its price, at
  # minimum -- without those two, the scraper doesn't have enough to save
  # a usable row (and the unique index in the migration would reject a
  # blank source/source_id pair anyway).
  validates :source, presence: true
  validates :source_id, presence: true
  validates :price, presence: true

  # `scope` defines a reusable, chainable query -- `Listing.in_price_range`
  # reads just like a method call but actually builds a WHERE clause.
  # This mirrors the `WHERE price >= 200 AND price <= 350` condition that
  # Python's database.py repeats in get_top_listings, get_stats, and
  # history.py every single time -- here it's defined once and reused.
  scope :in_price_range, -> { where(price: MIN_PRICE..MAX_PRICE) }
  # Another reusable scope -- listings good enough to be worth a person's
  # attention, i.e. score at or above the alert threshold.
  scope :good, -> { where(score: MIN_SCORE..) }
  # The default sort for the dashboard: best listings first, and among
  # equally-scored listings, cheapest first -- matches the
  # `ORDER BY score DESC, price ASC` in Python's get_top_listings.
  scope :best_first, -> { order(score: :desc, price: :asc) }

  # `should_skip?` decides whether a listing is worth saving at all --
  # `self.class` here means this can be called as `Listing.should_skip?(title)`
  # without needing an actual instance built first.
  def self.should_skip?(title)
    # `.present?` guards against a blank/nil title matching nothing and
    # slipping through; `match?` just checks true/false without allocating
    # a MatchData object we don't need.
    title.present? && SKIP_PATTERN.match?(title)
  end

  # `score_for` runs the same scoring math as Python's `score_listing`,
  # turning a title + price into a 0-100 quality number. Kept as a class
  # method (rather than an instance method) because the scraper needs to
  # score a listing BEFORE it decides whether to save it as a row at all.
  def self.score_for(title, price)
    # A listing whose title contains a "bad" word (shared room, couch,
    # RV, etc.) is worthless to us no matter what else is true about it,
    # so we bail out with zero immediately.
    return 0 if title.present? && BAD_WORDS.match?(title)

    # Every listing starts at a baseline of 50 -- "neutral," neither good
    # nor bad -- and then gets nudged up or down from there.
    score = 50

    # Good keywords (private, furnished, near ASU, etc.) are worth a solid
    # bump since they're strong positive signals.
    score += 20 if title.present? && GOOD_WORDS.match?(title)

    # The sweet-spot price range gets the biggest boost; the wider
    # acceptable range gets a small one; anything over budget gets
    # penalized. This three-way if/elsif ladder matches Python's exactly.
    if price.between?(220, 300)
      score += 15
    elsif price.between?(200, 350)
      score += 5
    elsif price > 350
      score -= 10
    end

    # Downcasing once and reusing it avoids repeating `title.downcase` on
    # every check below -- small thing, but it's what the Python version's
    # repeated `title.lower()` calls were doing implicitly each time.
    lower_title = title.to_s.downcase

    # "Private" is such a strong signal it gets rewarded twice -- once via
    # GOOD_WORDS above, once again here -- exactly mirroring the Python
    # version's (slightly redundant, but intentional) double-credit.
    score += 15 if lower_title.include?("private")
    # A listing explicitly advertised as "room for rent" (and NOT also
    # described as "shared") is a strong, unambiguous match for what we want.
    score += 10 if lower_title.include?("room for rent") && !lower_title.include?("shared")
    # Proximity language ("blocks from," "near") is a mild positive signal.
    score += 5 if lower_title.include?("blocks from") || lower_title.include?("near")

    # Clamp the final number into the 0-100 range so none of the additions
    # above can push a listing above 100 or below 0.
    score.clamp(0, 100)
  end

  # Convenience instance method so a view or job can just call
  # `listing.good?` instead of repeating the `score >= MIN_SCORE` check
  # everywhere it's needed.
  def good?
    score.to_i >= MIN_SCORE
  end
end
