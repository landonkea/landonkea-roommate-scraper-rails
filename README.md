# Roommate Scraper (Rails)

This is a Rails 8 rewrite of a Python scraper. Every night it checks
Craigslist and half a dozen room-rental sites (PadSplit, SpareRoom,
Roomster, and a few others) across Arizona, looks for rooms between $200
and $350 a month, scores each listing on how good a match it is, and
posts the good ones to a Discord channel. A small web dashboard shows
whatever it found, sorted best-first.

Nothing here needs a person watching it. You set a Discord webhook URL
once, and from then on the app scrapes on its own schedule and pings you
when something worth looking at shows up.

## How the pieces fit together

If you've never read code before, here's what each folder is actually
doing, in plain English:

- **`app/models/listing.rb`** — the definition of "a listing." One row in
  the database per room we've found. This file also holds the scoring
  math: given a title and a price, it works out a 0-100 score for how
  good a match the room is (private room = good, "shared living room
  with a couch" = bad, that sort of thing).
- **`app/services/scrapers/craigslist_scraper.rb`** — downloads
  Craigslist's search results page as plain HTML and picks the listings
  out of it. Craigslist doesn't need a real browser to read, just a
  normal web request.
- **`app/services/scrapers/browser_scraper.rb`** — handles every OTHER
  site (PadSplit, SpareRoom, Roomster, Cirtru, RoommateNation, iRoomit).
  These sites only show their listings after their own JavaScript runs,
  so this file drives an actual headless Chrome browser to load the page
  and read what ends up on screen.
- **`app/services/scrapers/listing_extractor.rb`** — a small helper that
  takes a messy blob of text off a listing card and pulls a price and a
  title out of it. Used by `browser_scraper.rb`.
- **`app/services/discord_notifier.rb`** — builds and sends the Discord
  message for one listing.
- **`app/services/scrape_runner.rb`** — the conductor. Wipes yesterday's
  listings, runs every scraper in order, and logs a short summary.
- **`app/jobs/scrape_listings_job.rb`** — a background job that calls
  `ScrapeRunner`. "Background" means it runs on its own, separately from
  anyone visiting the website — nobody has to sit and wait for a scrape
  to finish.
- **`config/recurring.yml`** — tells Rails' job scheduler (Solid Queue)
  to run that job automatically every day at 6:00 AM Arizona time. No
  cron job or GitHub Action needed; it's built into the app itself.
- **`app/controllers/listings_controller.rb`** and
  **`app/views/listings/index.html.erb`** — the dashboard page. Reads
  whatever's currently in the database and displays it as a table, with
  a dropdown to filter by site and a checkbox to show only the good ones.
- **`db/migrate/..._create_listings.rb`** — the blueprint for the
  `listings` database table: which columns exist, what type each one is.

## Why every run starts by deleting old listings

This might look backwards at first, but it matches how the original
Python version worked: `ScrapeRunner` empties the `listings` table before
every scrape rather than keeping a running history. That means it's a
daily snapshot — "here's what's available right now" — not a "notify me
once and never again" system. A room you saw yesterday will get a fresh
Discord alert today if it's still listed and still scores well. If you'd
rather it only ever alert once per listing, that's a one-line change in
`app/services/scrape_runner.rb` (drop the `Listing.delete_all` call and
rely on the unique index instead), just not what this port does by
default.

## Running it locally

You'll need Ruby 3.4.9 and Rails 8.1 installed (this repo assumes
`rbenv`, matching the other Rails apps in this collection).

```
bundle install
bin/rails db:prepare
bin/rails server
```

Then visit `http://localhost:3000` for the dashboard.

To actually run a scrape by hand instead of waiting for the daily
schedule, open a Rails console and call the runner directly:

```
bin/rails console
ScrapeRunner.call
```

For the background job scheduler (needed if you want the automatic daily
run to actually fire) run:

```
bin/jobs
```

alongside the web server.

## Environment variables

Copy `.env.example` to `.env` and fill in what you need:

- **`DISCORD_WEBHOOK_URL`** — where alerts get posted. Get one from
  Discord: open your server, go to Settings → Integrations → Webhooks →
  New Webhook, then copy the URL. Leave it blank and the app still runs
  fine, it just logs listings instead of posting them anywhere.
- **`BROWSER_PATH`** — optional, only needed if the headless-browser gem
  can't find Chrome on its own. The Docker image sets this automatically.

`.env` is listed in `.gitignore` so your real webhook URL never ends up
on GitHub. `.env.example` has no real values in it, just the variable
names — that one's safe to commit.

## Running the tests

```
bin/rails test
```

This runs 41 tests covering the scoring math, the skip-listing filter,
both scrapers (using fake stubbed-out web pages, no real internet
requests happen during tests), the Discord notifier, and the dashboard
page. All green as of this writing.

## Deploying / Docker

`bin/rails generate` already set up a production-ready `Dockerfile` (this
came from Rails itself, not written by hand for this project). It builds
with:

```
docker build -t landonkea-roommate-scraper-rails .
```

One thing worth knowing: the Dockerfile installs `chromium` inside the
image specifically so the headless-browser scrapers work once deployed —
without it, PadSplit/SpareRoom/etc. scraping would silently fail in
production (it wouldn't crash the app, it just wouldn't find anything on
those sites).

## What's different from the Python version, and why

- **Ferrum instead of Playwright.** Ferrum is the closest Ruby
  equivalent to Playwright — it drives a real headless Chrome browser the
  same way. The one thing it doesn't have is an equivalent to
  `playwright-stealth`, the anti-bot-detection layer the Python version
  used. That means these six JS-rendered sites may get blocked more
  often here than they did in Python. Craigslist (plain HTML, no browser
  needed) is unaffected.
- **No GitHub Pages history dashboard.** The Python version appended a
  daily summary to `docs/data/history.json` for a separate static
  GitHub Pages trend chart. This rewrite's dashboard reads straight out
  of the live database instead, so that separate static-site pipeline
  wasn't rebuilt — the live dashboard already shows current data without it.
- **Scheduling moved into the app.** The Python version's daily run was
  triggered by a GitHub Actions cron job. This version uses Solid
  Queue's own recurring-task scheduler (`config/recurring.yml`) instead,
  set to the same time (6:00 AM Arizona, which is always 13:00 UTC —
  Arizona doesn't observe daylight saving time). Same schedule, just
  running inside the app rather than depending on an external CI runner.

Everything else — the price range, the scoring formula, the skip
patterns, the Discord embed format and colors, the list of cities and
regions — is a direct port with no logic changes.
