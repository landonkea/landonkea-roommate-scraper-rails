require "test_helper"

# DiscordNotifier is the piece responsible for actually telling a human
# about a good listing -- these tests stub Discord's webhook endpoint so
# we can check exactly what gets sent and how errors get handled, without
# posting to a real Discord channel during test runs.
class DiscordNotifierTest < ActiveSupport::TestCase
  setup do
    @listing = listings(:great_room)
  end

  test "does nothing and returns false when no webhook URL is configured" do
    # Minitest's `stub` temporarily replaces ENV.fetch for the duration
    # of this block only, so we don't have to worry about a real
    # DISCORD_WEBHOOK_URL leaking in from the test machine's environment.
    ENV.stub(:fetch, nil) do
      assert_not DiscordNotifier.send_alert(@listing)
    end
  end

  test "posts an embed with the listing's score, price, and title" do
    ENV["DISCORD_WEBHOOK_URL"] = "https://discord.com/api/webhooks/123/abc"

    request = stub_request(:post, "https://discord.com/api/webhooks/123/abc")
      .with { |req|
        body = JSON.parse(req.body)
        embed = body["embeds"].first
        embed["title"].include?("90/100") &&
          embed["title"].include?("$275") &&
          embed["url"] == @listing.url &&
          embed["fields"].any? { |f| f["name"] == "Score" && f["value"] == "90/100" }
      }
      .to_return(status: 204)

    assert DiscordNotifier.send_alert(@listing)
    assert_requested(request)
  ensure
    ENV.delete("DISCORD_WEBHOOK_URL")
  end

  test "retries once after a 429 rate-limit response" do
    ENV["DISCORD_WEBHOOK_URL"] = "https://discord.com/api/webhooks/123/abc"

    stub_request(:post, "https://discord.com/api/webhooks/123/abc")
      .to_return(
        { status: 429, body: { retry_after: 0.01 }.to_json, headers: { "Content-Type" => "application/json" } },
        { status: 204 }
      )

    assert DiscordNotifier.send_alert(@listing)
  ensure
    ENV.delete("DISCORD_WEBHOOK_URL")
  end

  test "returns false and does not raise when Discord is unreachable" do
    ENV["DISCORD_WEBHOOK_URL"] = "https://discord.com/api/webhooks/123/abc"

    stub_request(:post, "https://discord.com/api/webhooks/123/abc").to_timeout

    assert_not DiscordNotifier.send_alert(@listing)
  ensure
    ENV.delete("DISCORD_WEBHOOK_URL")
  end
end
