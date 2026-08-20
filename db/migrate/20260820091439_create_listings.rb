# This migration is the Ruby version of the Python project's
# `CREATE TABLE IF NOT EXISTS rooms` statement in database.py -- it builds
# the one table this whole app cares about: every room/roommate listing we
# have ever pulled off Craigslist, PadSplit, or the other rental sites.
class CreateListings < ActiveRecord::Migration[8.1]
  # Rails calls this method to figure out what to do; `change` lets Rails
  # work out the up/down migration automatically since everything below is
  # a simple, reversible operation (just creating a table and some indexes).
  def change
    # `create_table :listings` opens up the block below and, once it runs,
    # issues the actual `CREATE TABLE listings (...)` SQL against the database.
    create_table :listings do |t|
      # Which site this came from -- "craigslist", "padsplit", "spareroom", etc.
      # Matches the Python `source` column exactly.
      t.string :source, null: false
      # The site's own ID (or URL, since most of these sites don't expose a
      # clean numeric ID) for this specific listing -- lets us tell "this is
      # the same listing we saw yesterday" from "this is a brand new one."
      t.string :source_id, null: false
      # The listing's title/headline text, e.g. "Private room near ASU".
      t.string :title
      # Monthly rent in dollars. Decimal (not integer) because Craigslist
      # prices can technically include cents, and decimal avoids floating
      # point rounding weirdness that a `float` column would risk.
      t.decimal :price, precision: 10, scale: 2
      # The actual link to the listing on the source site -- what the
      # Discord alert points people to.
      t.string :url
      # Free-text location/neighborhood string, e.g. "Tempe" or "Phoenix, AZ".
      t.string :location
      # The date we consider this listing "posted" -- for Craigslist we get
      # a real date, but for the JS-heavy sites we just stamp today's date
      # the same way the Python version did (they don't expose a clean date).
      t.date :posted_date
      # Our computed 0-100 quality score -- how good a match this listing
      # is for what the user's actually looking for. See Listing#score in
      # the model for exactly how this number gets calculated.
      t.integer :score, default: 0, null: false
      # The first time our scraper ever saw this exact listing. Used to
      # answer "is this new since last run?" without needing a separate
      # table -- if this timestamp was set moments ago, it's brand new.
      t.datetime :first_seen_at, null: false

      # Adds `created_at` and `updated_at` columns automatically -- Rails'
      # standard bookkeeping, separate from `first_seen_at` above, which
      # tracks scraper-relevant history rather than plain row bookkeeping.
      t.timestamps
    end

    # A single listing (same source_id on the same source) should only ever
    # exist once in this table -- this unique index is what makes
    # `find_or_create_by` safe to call over and over as the scraper re-runs
    # without ever creating duplicate rows for a listing we've already saved.
    add_index :listings, [ :source, :source_id ], unique: true
    # The dashboard sorts by score constantly, so an index here keeps that
    # query fast even once the table has thousands of rows in it.
    add_index :listings, :score
  end
end
