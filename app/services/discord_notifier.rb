# Posts a "here's a good listing" message into a Discord channel via a
# webhook -- a webhook is just a special URL Discord gives you that
# accepts a JSON POST and turns it into a message, no bot login required.
# This is a straight port of Python's discord.py, including its retry
# behavior when Discord temporarily rate-limits us.
class DiscordNotifier
  # Discord's webhook API replies with a plain 204 No Content on success
  # (no body, just "yep, got it") -- we check for this exact status below
  # to know the message actually went through.
  SUCCESS_STATUS = 204
  # HTTP 429 is the standard "you're sending requests too fast, slow down"
  # status code -- Discord uses it just like most rate-limited APIs do.
  RATE_LIMITED_STATUS = 429

  # `send_alert` builds and posts one Discord embed for a single listing.
  # `listing` is an ActiveRecord::Listing instance -- pulling the fields
  # we need straight off it keeps the caller (the scrape job) simple.
  def self.send_alert(listing)
    # `ENV.fetch("DISCORD_WEBHOOK_URL", nil)` reads the webhook URL from
    # the environment rather than ever hardcoding it in source -- if it's
    # missing we still want the scraper to keep running, just without
    # actually notifying anyone, so we log and bail instead of raising.
    webhook_url = ENV.fetch("DISCORD_WEBHOOK_URL", nil)
    if webhook_url.blank?
      Rails.logger.info("[DiscordNotifier] no webhook configured, skipping alert for: #{listing.title}")
      return false
    end

    # Green for a great score, yellow for a decent one, orange for
    # anything that barely cleared the alert threshold -- same three
    # color bands and cutoffs (70, 50) as the Python version.
    color = if listing.score >= 70
      0x00ff00
    elsif listing.score >= 50
      0xffff00
    else
      0xff9900
    end

    # Discord embeds are just a nested hash structure -- this mirrors the
    # exact fields the Python version sent, including truncating the
    # title to 75 characters so the embed title doesn't get cut off oddly
    # by Discord's own display limits.
    embed = {
      title: "[#{listing.score}/100] $#{format('%.0f', listing.price)}/mo - #{listing.title.to_s[0, 75]}",
      url: listing.url,
      color: color,
      fields: [
        { name: "Location", value: listing.location.presence || "AZ", inline: true },
        { name: "Score", value: "#{listing.score}/100", inline: true }
      ],
      footer: { text: "Found #{Time.current.strftime('%m/%d %I:%M %p')}" }
    }

    post_embed(webhook_url, embed)
  end

  # Pulled out as its own method so the retry-on-429 logic (which posts
  # twice in the worst case) doesn't clutter up `send_alert` above.
  def self.post_embed(webhook_url, embed)
    # `Faraday.post` fires the actual HTTP request; the block configures
    # the request body as JSON and sets a request timeout so a hung
    # connection can't stall the whole scrape job.
    response = Faraday.post(webhook_url) do |req|
      req.headers["Content-Type"] = "application/json"
      req.options.timeout = 10
      req.body = { embeds: [ embed ] }.to_json
    end

    if response.status == SUCCESS_STATUS
      # Success -- nothing else to do.
      true
    elsif response.status == RATE_LIMITED_STATUS
      # Discord tells us exactly how long to wait in the response body;
      # `retry_after` is in seconds, and we pad it by half a second same
      # as the Python version did, then try exactly once more.
      retry_after = JSON.parse(response.body)["retry_after"] || 2
      sleep(retry_after + 0.5)
      retry_response = Faraday.post(webhook_url) do |req|
        req.headers["Content-Type"] = "application/json"
        req.options.timeout = 10
        req.body = { embeds: [ embed ] }.to_json
      end
      retry_response.status == SUCCESS_STATUS
    else
      # Anything else (Discord down, bad webhook, etc.) -- log it and
      # move on rather than blowing up the whole scrape run over one
      # failed notification.
      Rails.logger.warn("[DiscordNotifier] unexpected status #{response.status}")
      false
    end
  rescue Faraday::Error => e
    # Network hiccups shouldn't crash the scraper either -- same
    # "swallow it and keep going" behavior as Python's bare `except:`.
    Rails.logger.warn("[DiscordNotifier] request failed: #{e.message}")
    false
  end
end
