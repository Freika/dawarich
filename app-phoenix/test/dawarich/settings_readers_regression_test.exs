defmodule Dawarich.SettingsReadersRegressionTest do
  use ExUnit.Case, async: false

  alias Dawarich.{Repo, UserSettings}
  alias Dawarich.Test.RailsUser
  alias Dawarich.Digests.Context
  alias DawarichWeb.StatsLive.Month

  @now ~U[2026-10-07 00:00:00Z]
  @env %{"TIME_ZONE" => "UTC", "SELF_HOSTED" => "true"}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    env = Map.take(System.get_env(), ~w(TIME_ZONE SELF_HOSTED))
    System.put_env(@env)

    on_exit(fn ->
      for key <- Map.keys(@env) do
        if env[key], do: System.put_env(key, env[key]), else: System.delete_env(key)
      end
    end)

    user = RailsUser.insert!(%{id: 49891, email: "reader-regression@example.invalid"})
    %{user: user}
  end

  @tag review_r2: true
  test "malformed stored containers load digest context with Rails timezone defaults", %{
    user: user
  } do
    for raw <- [[], false, 0, "malformed"] do
      store(user, raw)
      context = Context.load!(Repo, user.id, now: @now, env: @env)
      assert context.effective_zone == "UTC"
      assert context.user_zone == "Etc/UTC"
      assert context.raw_zone == nil
      assert context.settings == UserSettings.safe(%{}, @env)
      assert_stored(user, raw)
    end
  end

  @tag review_r3: true
  test "malformed stored containers render monthly stats with Rails tile defaults", %{user: user} do
    for raw <- [[], false, 0, "malformed"] do
      store(user, raw)

      page =
        Month.page(%{user | settings: raw}, %{"year" => "2026", "month" => "9"}, page_context())

      assert page.tiles_url == ""
      assert page.tiles_fallback == "false"
      assert page.unit == "km"
      assert page.data.stat == nil
      assert_stored(user, raw)
    end
  end

  @tag review_matrix: true
  test "176 Rails oracle containers preserve nonraising behavior across all 17 reviewed readers",
       %{user: user} do
    corpus = File.read!("test/fixtures/settings_reader_oracle.json") |> Jason.decode!()
    assert length(corpus) == 176
    assert length(readers(user, %{})) == 17

    failures =
      for row <- corpus, reduce: [] do
        failures ->
          raw = row["input"]
          store(user, raw)
          assert UserSettings.safe(raw, @env) == row["normalized"]

          Enum.reduce(readers(user, raw), failures, fn {name, contract, call}, acc ->
            outcome = result(call)

            if Map.has_key?(row["contracts"][contract], "ok") and match?({:error, _}, outcome),
              do: [{name, raw, outcome} | acc],
              else: acc
          end)
      end

    assert failures == [], inspect(failures, limit: :infinity)
  end

  defp readers(user, raw) do
    [
      {"StatsFormat.unit", "distance", fn -> DawarichWeb.StatsFormat.unit(raw) end},
      {"Days.unit", "distance", fn -> Dawarich.Timeline.Days.unit(raw) end},
      {"Api.Params.unit", "distance", fn -> DawarichWeb.Api.Params.unit(nil, raw) end},
      {"Api.Params.min_minutes", "threshold", fn -> DawarichWeb.Api.Params.min_minutes(raw) end},
      {"Checker.threshold_seconds", "threshold",
       fn -> Dawarich.Achievements.Checker.threshold_seconds(raw) end},
      {"Visits.Settings.policy", "visits", fn -> Dawarich.Visits.Settings.policy(raw) end},
      {"TripSettings.read", "distance", fn -> Dawarich.TripSettings.read(raw) end},
      {"Calculation.minutes_between_routes", "minutes",
       fn -> Dawarich.Trips.Calculation.minutes_between_routes(raw) end},
      {"Sharing.enabled?", "family", fn -> Dawarich.Families.Sharing.enabled?(raw, @now) end},
      {"Sharing.config", "family_config", fn -> Dawarich.Families.Sharing.config(raw) end},
      {"UserTimeZone.zone", "timezone", fn -> Dawarich.UserTimeZone.zone(raw, @env) end},
      {"Admin.BackgroundPage.read", "background",
       fn -> Dawarich.Admin.BackgroundPage.read(%{settings: raw}) end},
      {"Thumbnail.configured?", "integration",
       fn -> Dawarich.Photos.Thumbnail.configured?(raw) end},
      {"ExploreFeatures.locale", "locale",
       fn -> Dawarich.Mail.ExploreFeatures.locale(raw, "en") end},
      {"Locale.resolve", "locale",
       fn -> DawarichWeb.Locale.resolve(nil, %{settings: raw}, %{}) end},
      {"Restore.locale", "locale",
       fn -> Dawarich.UserData.Restore.locale(Repo, user.id, %{locale: "en"}) end},
      {"Digests.Context.load!", "timezone",
       fn -> Context.load!(Repo, user.id, now: @now, env: @env) end}
    ]
  end

  defp result(call) do
    {:ok, call.()}
  rescue
    error -> {:error, error.__struct__}
  end

  defp store(user, raw),
    do: Repo.query!("UPDATE users SET settings=$2 WHERE id=$1", [user.id, raw], log: false)

  defp assert_stored(user, raw),
    do:
      assert(
        Repo.query!("SELECT settings FROM users WHERE id=$1", [user.id], log: false).rows == [
          [raw]
        ]
      )

  defp page_context,
    do: %{locale: "en", now: @now, self_hosted: true, base_url: "http://example.invalid"}
end
