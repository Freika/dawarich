defmodule DawarichWeb.SettingsParityTest do
  use Dawarich.JobsCase, async: false

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Dawarich.Repo
  alias Dawarich.Test.RailsUser

  @dir "test/fixtures/settings"
  @corpus "test/fixtures/settings_corpus.json" |> File.read!() |> Jason.decode!()
  @env ~w(TIME_ZONE MANAGER_URL OIDC_PROVIDER_NAME CHIBICHANGE_WIDGET_HOST SMTP_SERVER)
  @retired_stimulus "[data-controller], [data-action], [data-activity-heatmap-target], [data-upload-target], [data-turbo], [data-turbo-method], [data-turbo-confirm], [data-turbo-stream]"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    previous = Map.new(["JWT_SECRET_KEY" | @env], &{&1, System.get_env(&1)})
    for key <- @env, do: System.delete_env(key)
    System.put_env("JWT_SECRET_KEY", "phoenix-a5-jwt-fixture-secret-not-for-production")

    on_exit(fn ->
      for {key, value} <- previous do
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end
    end)
  end

  @fixtures Path.wildcard("test/fixtures/settings/*.json")
  if length(@fixtures) < 10,
    do: raise("expected 10 settings fixtures, found #{length(@fixtures)}")

  for file <- @fixtures do
    @name Path.basename(file, ".json")

    test "#{@name} retains native overview values period access and locale" do
      state = @dir |> Path.join(@name <> ".json") |> File.read!() |> Jason.decode!()
      {:ok, now, 0} = DateTime.from_iso8601(state["now"])
      user = seed!(state)
      locale = DawarichWeb.Locale.resolve(nil, user, %{})
      uri = URI.parse(state["path"])

      _context = %{
        locale: locale,
        now: now,
        self_hosted: state["self_hosted"],
        base_url: "http://www.example.com",
        rails_csrf_token: "CSRF",
        current_user: user,
        smtp: state["smtp"],
        two_factor: state["two_factor"],
        supporter: state["supporter"],
        zones: Enum.map(@corpus["time_zone_options"], fn [label, iana] -> {label, iana} end)
      }

      assigns =
        Dawarich.Insights.page(
          user,
          URI.decode_query(uri.query || ""),
          Dawarich.Stats.context(user, now, state["self_hosted"])
        )

      query = URI.decode_query(uri.query || "")

      {:ok, data} =
        Dawarich.Insights.Pages.overview(Dawarich.Accounts.Scope.for_user(user, locale), query,
          now: now,
          self_hosted: state["self_hosted"]
        )

      for key <- [
            :totals,
            :available,
            :locked,
            :all_time,
            :year,
            :year_locked,
            :restricted,
            :heatmap
          ],
          do:
            assert(
              if(is_map(assigns[key]),
                do: Map.take(data[key], Map.keys(assigns[key])),
                else: data[key]
              ) == assigns[key]
            )

      phoenix =
        render_component(&DawarichWeb.InsightsLive.NativeParts.overview/1,
          data: Map.put(data, :more, false),
          query: query,
          path: "/insights",
          locale: locale
        )

      refute Enum.any?(LazyHTML.query(LazyHTML.from_document(phoenix), @retired_stimulus))
      refute phoenix =~ "turbo-frame"
      refute phoenix =~ "Chartkick"
      refute phoenix =~ "translation_missing"

      assert DawarichWeb.Layouts.page_title(
               locale,
               DawarichWeb.Translate.t(locale, "insights.index.insights", %{})
             ) == state["title"]
    end
  end

  defp seed!(state) do
    u = state["user"]

    RailsUser.insert!(%{
      id: u["id"],
      email: u["email"],
      settings: u["settings"],
      plan: u["plan"],
      status: u["status"],
      active_until: naive(u["active_until"]),
      api_key: u["api_key"],
      points_count: u["points_count"],
      theme: u["theme"],
      admin: u["admin"],
      provider: u["provider"],
      changelog_consent: u["changelog_consent"],
      subscription_source: u["subscription_source"]
    })

    Repo.insert_all(
      "stats",
      for s <- state["stats"] do
        %{
          id: s["id"],
          user_id: u["id"],
          year: s["year"],
          month: s["month"],
          distance: s["distance"],
          daily_distance: s["daily_distance"],
          toponyms: s["toponyms"],
          created_at: naive(s["created_at"]),
          updated_at: naive(s["updated_at"])
        }
      end
    )

    Repo.insert_all(
      "trip_sources",
      for t <- state["trip_sources"] do
        %{
          id: t["id"],
          user_id: u["id"],
          provider: t["provider"],
          base_url: t["base_url"],
          importing: t["importing"],
          last_synced_at: naive(t["last_synced_at"]),
          last_error: t["last_error"],
          status: t["status"],
          created_at: naive(t["created_at"]),
          updated_at: naive(t["updated_at"])
        }
      end
    )

    Dawarich.Accounts.get(u["id"])
  end

  defp naive(nil), do: nil

  defp naive(value) do
    {:ok, at, 0} = DateTime.from_iso8601(value)
    DateTime.to_naive(at)
  end
end
