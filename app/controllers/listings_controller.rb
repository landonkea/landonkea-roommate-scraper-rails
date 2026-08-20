# Serves the dashboard page -- the one screen a person actually looks at
# to see what the scraper found. Nothing here writes to the database;
# this controller only ever reads and displays what ScrapeListingsJob
# already saved.
class ListingsController < ApplicationController
  # `index` handles GET /listings (and GET / via the root route) --
  # Rails automatically renders app/views/listings/index.html.erb after
  # this method runs, using whatever instance variables (@listings,
  # @sources, etc.) got set below.
  def index
    # Start from every listing, best-scored first -- `best_first` is the
    # scope defined on the model so this line stays readable instead of
    # spelling out `order(score: :desc, price: :asc)` here too.
    scope = Listing.best_first

    # `params[:source]` is whatever the "?source=padsplit" query string
    # holds, if anything -- letting someone filter the dashboard down to
    # just one site's listings via the dropdown in the view.
    if params[:source].present?
      scope = scope.where(source: params[:source])
    end

    # A "good listings only" checkbox in the view sends `good=1`; only
    # apply the score filter when that box was actually checked, so the
    # default view still shows everything.
    if params[:good].present?
      scope = scope.good
    end

    # `@listings` is what the view loops over to render each row of the
    # dashboard table.
    @listings = scope

    # `distinct.pluck(:source).sort` builds the list of sites to show in
    # the filter dropdown -- pulled fresh from whatever's actually in the
    # database right now rather than a hardcoded list, so it stays
    # accurate even if a new source gets added to the scraper later.
    @sources = Listing.distinct.pluck(:source).compact.sort

    # A short stats line at the top of the page -- total listings in our
    # target price range, and how many of those are "good" (score >= 50).
    # Mirrors the summary line Python's main.py printed after every run.
    @total_count = Listing.in_price_range.count
    @good_count = Listing.in_price_range.good.count
  end
end
