defmodule DawarichWeb.RateLimit.Rules do
  @moduledoc false

  alias Dawarich.ReleaseMigration
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias DawarichWeb.RateLimit.Request

  @plan_limits %{"lite" => 200, "pro" => 1_000, "family" => 1_000}
  @points ~w(/api/v1/points /api/v1/owntracks/points /api/v1/overland/batches)
  @heavy ~w(/api/v1/recalculations /api/v1/points/reapply_anomaly_filter)
  @two_factor ~w(/api/v1/users/me/two_factor /api/v1/users/me/two_factor/setup /api/v1/users/me/two_factor/confirm /api/v1/users/me/two_factor/backup_codes)
  @oauth ~w(/api/v1/auth/apple /api/v1/auth/google)
  @json_api ~w(/api/v1/auth/login /api/v1/auth/otp_challenge)
  @max_json 16_384

  def plan_limits, do: @plan_limits

  def limit(:plan, inputs), do: Map.get(@plan_limits, inputs.plan, 1_000)
  def limit(limit, _inputs), do: limit

  def blocklist_path?(f),
    do:
      f.throttle_path == "/users/sign_in" or (f.throttle_path in @json_api and not f.self_hosted)

  def blocked?(f),
    do: f.method == "POST" and f.json and f.content_length > @max_json and blocklist_path?(f)

  def method?({_name, _limit, _period, :any, _path, _needs, _key}, _method), do: true

  def method?({_name, _limit, _period, methods, _path, _needs, _key}, method),
    do: method in methods

  def throttles do
    [
      {"api/token", :plan, 3_600, :any, cloud(&api?/1), [:api_key], &api_token/1},
      {"api/tiles", 10_000, 3_600, :any, cloud(under("/api/v1/tiles/")), [:api_key],
       &prefixed(&1, "tiles:")},
      {"api/tiles_burst", 600, 30, :any, cloud(under("/api/v1/tiles/")), [:api_key],
       &prefixed(&1, "tiles_burst:")},
      {"api/points_creation", 10_000, 3_600, ["POST"], cloud(within(@points)), [:api_key],
       &prefixed(&1, "points_creation:")},
      {"api/heavy_recompute", 5, 3_600, ["POST"], cloud(within(@heavy)), [:api_key],
       &prefixed(&1, "heavy_recompute:")},
      {"logins/ip", 20, 60, ["POST"], cloud(at("/users/sign_in")), [:ip], &ip/1},
      {"logins/email", 5, 60, ["POST"], cloud(at("/users/sign_in")), [:body], &web_email/1},
      {"logins/api_ip", 20, 60, ["POST"], cloud(at("/api/v1/auth/login")), [:ip], &ip/1},
      {"logins/api_email", 5, 60, ["POST"], cloud(at("/api/v1/auth/login")), [:body],
       &api_email/1},
      {"signups/api_ip_burst", 5, 60, ["POST"], cloud(at("/api/v1/auth/register")), [:ip], &ip/1},
      {"signups/api_ip_hourly", 20, 3_600, ["POST"], cloud(at("/api/v1/auth/register")), [:ip],
       &ip/1},
      {"oauth/token_exchange", 30, 60, ["POST"], cloud(within(@oauth)), [:ip], &ip/1},
      {"apple_web_callback_per_ip", 20, 60, ["POST"], cloud(at("/users/auth/apple/callback")),
       [:ip], &ip/1},
      {"users/exist", 600, 3_600, ["POST"], cloud(at("/api/v1/users/exist")), [:webhook],
       &webhook/1},
      {"api/auth/otp_challenge", 5, 900, ["POST"], cloud(at("/api/v1/auth/otp_challenge")), [:ip],
       &ip/1},
      {"api/auth/otp_challenge_token", 5, 900, ["POST"], cloud(at("/api/v1/auth/otp_challenge")),
       [:body], &challenge/1},
      {"users/otp_challenge_session", 5, 900, ["POST"], cloud(at("/users/otp_challenge")),
       [:session, :ip], &otp_session/1},
      {"users/otp_challenge_ip", 20, 900, ["POST"], cloud(at("/users/otp_challenge")), [:ip],
       &ip/1},
      {"auth/account_link_challenge_session", 5, 900, ["POST"],
       at("/auth/account_link/challenge"), [:session, :ip], &link_session/1},
      {"auth/account_link_challenge_ip", 20, 900, ["POST"], at("/auth/account_link/challenge"),
       [:ip], &ip/1},
      {"api/users/two_factor_sensitive", 5, 900, ["POST", "DELETE"], cloud(within(@two_factor)),
       [:api_key], &prefixed(&1, "two_factor_sensitive:")},
      {"trial/welcome", 30, 60, ["GET"], cloud(at("/trial/welcome")), [:ip], &ip/1},
      {"signups/ip_burst", 5, 60, ["POST"], cloud(at("/users")), [:ip], &ip/1},
      {"signups/ip_hourly", 20, 3_600, ["POST"], cloud(at("/users")), [:ip], &ip/1},
      {"admin/flipper", 30, 300, :any, cloud(under("/admin/flipper")), [:ip], &ip/1},
      {"shared_links/viewer", 120, 60, :any, cloud(&viewer?/1), [:ip], &ip/1},
      {"shared_links/cable", 120, 60, :any, cloud(at("/cable")), [:params, :ip],
       &present_ip(&1, "share_id")},
      {"shared_links/unlock", 5, 300, ["POST"], &(&1.unlock_id != nil), [:ip], &unlock/1},
      {"api/v1/imports/pending CREATE", 60, 3_600, ["POST"],
       cloud(under("/api/v1/imports/pending")), [:ip], &ip/1},
      {"imports/claim attempts", 30, 3_600, ["GET"], cloud(under("/users/sign_up")),
       [:params, :ip], &present_ip(&1, "import_ticket")}
    ]
  end

  def evaluate(entries, now, increment) do
    Enum.reduce_while(entries, {:pass, [], nil}, fn {name, limit, period, discriminator},
                                                    {:pass, counted, token} ->
      key = key(now, period, name, discriminator)
      ttl = period - rem(now, period) + 1

      case increment.(key, ttl) do
        {:ok, count} ->
          data = %{limit: limit, count: count, period: period}
          counted = counted ++ [{key, ttl}]
          token = if name == "api/token", do: data, else: token

          if count > limit,
            do: {:halt, {:throttled, counted, data}},
            else: {:cont, {:pass, counted, token}}

        {:error, reason} ->
          {:halt, {:defer, counted, reason}}
      end
    end)
  end

  def key(now, period, name, discriminator),
    do: "rack::attack:#{div(now, period)}:#{name}:#{normalize(discriminator)}"

  def normalize(discriminator),
    do: discriminator |> to_string() |> ReleaseMigration.ruby_strip() |> String.downcase()

  defp cloud(fun), do: fn f -> not f.self_hosted and fun.(f) end
  defp at(path), do: fn f -> f.throttle_path == path end
  defp within(paths), do: fn f -> f.throttle_path in paths end
  defp under(prefix), do: fn f -> String.starts_with?(f.path, prefix) end

  defp api?(f),
    do: String.starts_with?(f.path, "/api/") and not String.starts_with?(f.path, "/api/v1/tiles/")

  defp viewer?(f),
    do:
      Regex.match?(~r/\A\/s\/[^\/]+\z/, f.path) or String.starts_with?(f.path, "/api/v1/shared/")

  defp ip(i), do: i.ip
  defp unlock(i), do: "#{i.ip}:#{i.unlock_id}"
  defp api_token(i), do: if(Ruby.present?(i.api_key) and i.plan, do: i.api_key)
  defp prefixed(i, prefix), do: if(Ruby.present?(i.api_key), do: prefix <> i.api_key)
  defp present_ip(i, field), do: if(Ruby.present?(i.params[field]), do: i.ip)
  defp api_email(i), do: Request.ruby_to_s(i.body["email"])
  defp webhook(i), do: digest(i.webhook || "")
  defp challenge(i), do: digest(Request.ruby_to_s(i.body["challenge_token"]) || "")

  defp web_email(i) do
    case i.body["user"] do
      %{} = user -> Request.ruby_to_s(user["email"])
      _ -> nil
    end
  end

  defp otp_session(i) do
    case i.session["otp_user_id"] do
      value when value in [nil, false] -> i.ip
      value -> Request.ruby_to_s(value)
    end
  end

  defp link_session(i) do
    case i.session["pending_oauth_link"] do
      %{"user_id" => value} when value not in [nil, false] -> Request.ruby_to_s(value)
      %{} -> nil
      _ -> i.ip
    end
  end

  defp digest(value) do
    if Ruby.present?(value),
      do: :sha256 |> :crypto.hash(value) |> Base.encode16(case: :lower) |> binary_part(0, 32)
  end
end
