# Every JavaScript-rendered rental site we scrape (PadSplit, SpareRoom,
# Roomster, etc.) hands us the same shape of raw material: a link's href
# plus a big blob of plain innerText scraped off whatever card that link
# sits inside. None of these sites give us clean, consistent HTML classes
# to select against, so we're stuck guessing at structure from that text
# blob -- this class is that guess, pulled out on its own so it can be
# tested without needing a real browser running. It's a direct port of
# Python's `_extract_listing` helper in scraper.py.
module Scrapers
  class ListingExtractor
    # Matches a dollar amount like "$275" or "$1,200" -- the `\$` escapes
    # the dollar sign (it's a regex metacharacter otherwise), and
    # `[\d,]+` grabs digits and commas together so "1,200" comes through
    # as one match instead of stopping at the comma.
    PRICE_PATTERN = /\$([\d,]+)/

    # `call` is the one public entry point -- pass it the raw text blob
    # from a listing's container, get back a price/title pair (or nil if
    # there's nothing usable in there). `self.call` means callers just
    # write `Scrapers::ListingExtractor.call(text)` with no instance needed.
    def self.call(text)
      # No dollar amount anywhere in the text means this isn't actually a
      # listing card (could be a nav link, an ad, anything) -- bail out.
      match = PRICE_PATTERN.match(text.to_s)
      return nil unless match

      # `match[1]` is the digits-and-commas capture group; stripping the
      # commas and converting to a float gives us a usable numeric price,
      # same as Python's `float(price_match.group(1).replace(',', ''))`.
      price = match[1].delete(",").to_f

      # Split the blob into individual lines, dropping blank ones --
      # `strip` trims whitespace off each line, and the `select` below
      # only keeps lines that survived that trim with content left over.
      lines = text.to_s.split("\n").map(&:strip).select { |line| line.present? }

      # We're hunting for the title: the first line that's reasonably
      # long (more than 10 characters, so we skip stray short fragments)
      # and doesn't itself contain a dollar sign (so we skip price lines).
      title = lines.find { |line| line.length > 10 && !line.include?("$") }

      # If nothing matched that heuristic, fall back to whatever the
      # first line was -- better than an empty title. If there were no
      # lines at all, fall back to a generic placeholder.
      title ||= lines.first || "Room listing"

      # Return both values as a two-element array -- callers destructure
      # this as `price, title = extractor.call(text)`.
      [ price, title ]
    end
  end
end
