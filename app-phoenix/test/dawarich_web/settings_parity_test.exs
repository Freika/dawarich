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

  for name <-
        ~w(general_en general_de general_cloud_de general_supporter_en general_unverified_en general_nosmtp_en general_cloud_en general_admin_en) do
    @general_name name
    test "#{@general_name} renders the Rails 1.16.0 general settings DOM" do
      state = @dir |> Path.join(@general_name <> ".json") |> File.read!() |> Jason.decode!()
      {:ok, now, 0} = DateTime.from_iso8601(state["now"])
      user = seed!(state)
      locale = DawarichWeb.Locale.resolve(nil, user, %{})

      context = %{
        locale: locale,
        now: now,
        self_hosted: state["self_hosted"],
        current_user: user,
        smtp: state["smtp"],
        two_factor: state["two_factor"],
        supporter: state["supporter"],
        rails_csrf_token: "CSRF",
        zones: Enum.map(@corpus["time_zone_options"], fn [label, iana] -> {label, iana} end)
      }

      {:ok, socket} =
        DawarichWeb.SettingsLive.General.mount(%{}, %{}, %Phoenix.LiveView.Socket{
          assigns: Map.put(context, :__changed__, %{})
        })

      html = render_component(&DawarichWeb.SettingsLive.General.render/1, socket.assigns)
      rails = File.read!(Path.join(@dir, @general_name <> ".html"))
      Dawarich.Test.SettingsParity.dump(@general_name, rails, html)

      html =
        if state["self_hosted"] and state["smtp"] and user.admin do
          assert LazyHTML.from_fragment(html)
                 |> LazyHTML.query("#native-send-test-email")
                 |> LazyHTML.attribute("href") == ["#"]

          String.replace(html, "href=\"#\"", "href=\"/settings/general/test_email\"")
        else
          html
        end

      actual = Dawarich.Test.ParityHTML.normalize(html)
      expected = Dawarich.Test.ParityHTML.normalize(rails)
      assert actual == expected, Dawarich.Test.ParityHTML.first_difference(actual, expected)
    end
  end

  for name <-
        ~w(disabled enabled setup verify_bad verify_good disabled_de enabled_de setup_de verify_bad_de verify_good_de cloud_disabled cloud_enabled cloud_setup cloud_verify_bad cloud_verify_good cloud_disabled_de cloud_enabled_de cloud_setup_de cloud_verify_bad_de cloud_verify_good_de) do
    @factor_name name
    @tag :d5_two_factor
    test "two factor #{@factor_name} renders the Rails 1.16.0 management DOM" do
      directory =
        if String.starts_with?(@factor_name, "cloud_"),
          do: "test/fixtures/auth/two_factor/cloud",
          else: "test/fixtures/auth/two_factor"

      name = String.replace_prefix(@factor_name, "cloud_", "")
      rows = directory |> Path.join("requests.json") |> File.read!() |> Jason.decode!()
      row = Enum.find(rows, &(&1["name"] == name))
      rails = File.read!(Path.join(directory, name <> ".html"))
      doc = LazyHTML.from_fragment(rails)

      codes =
        doc |> LazyHTML.query("code.font-mono") |> Enum.map(&(LazyHTML.text(&1) |> String.trim()))

      secret = doc |> LazyHTML.query("details code") |> LazyHTML.text() |> String.trim()

      kind =
        cond do
          codes != [] -> :backup_codes
          secret != "" -> :verify
          true -> :show
        end

      html =
        render_component(&DawarichWeb.AuthTwoFactor.Form.page/1,
          locale: row["locale"],
          kind: kind,
          enabled: row["after"]["enabled"],
          self_hosted: row["self_hosted"] != false,
          admin: false,
          two_factor: true,
          rails_csrf_token: "CSRF",
          secret: secret,
          uri: Dawarich.Auth.TwoFactor.Totp.provisioning_uri(secret, row["email"]),
          codes: codes
        )

      Dawarich.Test.SettingsParity.dump("two_factor_" <> @factor_name, rails, html)

      if kind == :show do
        assert LazyHTML.from_fragment(html)
               |> LazyHTML.query("a[href='/settings/two_factor']")
               |> LazyHTML.attribute("aria-current") == ["page"]
      end

      rails =
        Enum.reduce(
          [
            {"card-body", "card-body min-w-0"},
            {"flex items-center gap-3 mb-4", "flex flex-wrap items-center gap-3 mb-4"},
            {"grid grid-cols-2 gap-2", "grid grid-cols-1 sm:grid-cols-2 gap-2"},
            {"block text-center text-xs font-mono p-2 bg-base-300 rounded truncate",
             "block text-center text-xs font-mono p-2 bg-base-300 rounded min-w-0 [overflow-wrap:anywhere] select-text"}
          ],
          rails,
          fn {from, to}, html -> String.replace(html, "class=\"#{from}\"", "class=\"#{to}\"") end
        )

      actual = factor_dom(html)
      expected = factor_dom(rails)
      assert actual == expected, Dawarich.Test.ParityHTML.first_difference(actual, expected)
    end
  end

  for name <-
        ~w(defaults cooldown_nil cooldown_recent cooldown_exact_hour lite_hint self_hosted_en self_hosted_de cloud_de lite_de cooldown_recent_de) do
    @visits_name name
    @tag :d5_visits
    test "visits #{@visits_name} renders the Rails 1.16.0 detection settings DOM" do
      directory = "test/fixtures/a8vv/settings"
      state = directory |> Path.join(@visits_name <> ".json") |> File.read!() |> Jason.decode!()
      row = hd(state["before"]["users"])
      user = seed!(%{"user" => row, "stats" => [], "trip_sources" => []})

      Repo.query!(
        "UPDATE users SET visits_redetected_at=$1 WHERE id=$2",
        [naive(row["visits_redetected_at"]), user.id],
        log: false
      )

      {:ok, now, 0} = DateTime.from_iso8601(state["now"])
      locale = DawarichWeb.Locale.resolve(nil, user, %{})

      context = %{
        current_user: user,
        current_scope: Dawarich.Accounts.Scope.for_user(user, locale),
        locale: locale,
        self_hosted: state["self_hosted"],
        now: now,
        rails_csrf_token: "CSRF"
      }

      {:ok, socket} =
        DawarichWeb.SettingsLive.Visits.mount(%{}, %{}, %Phoenix.LiveView.Socket{
          assigns: Map.put(context, :__changed__, %{})
        })

      page =
        Dawarich.Visits.WebSettings.page(
          user,
          Dawarich.Visits.WebSettings.load(Repo, user.id),
          now,
          state["self_hosted"]
        )

      html =
        render_component(
          &DawarichWeb.SettingsLive.Visits.render/1,
          Map.merge(socket.assigns, page)
        )

      rails = File.read!(Path.join(directory, @visits_name <> ".html"))
      Dawarich.Test.SettingsParity.dump("visits_" <> @visits_name, rails, html)
      actual = Dawarich.Test.ParityHTML.normalize(html)
      expected = Dawarich.Test.ParityHTML.normalize(rails)
      assert actual == expected, Dawarich.Test.ParityHTML.first_difference(actual, expected)
    end
  end

  @tag :d5_integrations
  test "integration service and account states render the Rails 1.16.0 settings DOM" do
    files = Path.wildcard("test/fixtures/settings/integrations_*.json")
    assert length(files) == 19

    for file <- files do
      Dawarich.FixtureCleanup.delete!(Repo, ~w(trip_sources stats users))
      state = file |> File.read!() |> Jason.decode!()
      user = seed!(state)
      {:ok, now, 0} = DateTime.from_iso8601(state["now"])
      locale = DawarichWeb.Locale.resolve(nil, user, %{})
      principal = Dawarich.Accounts.Principal.project(user)

      context = %{
        current_user: principal,
        current_scope: Dawarich.Accounts.Scope.for_user(principal, locale),
        locale: locale,
        self_hosted: state["self_hosted"],
        now: now,
        two_factor: state["two_factor"],
        rails_csrf_token: "CSRF"
      }

      {:ok, socket} =
        DawarichWeb.SettingsLive.Integrations.mount(%{}, %{}, %Phoenix.LiveView.Socket{
          assigns: Map.put(context, :__changed__, %{})
        })

      params = URI.decode_query(URI.parse(state["path"]).query || "")

      {:noreply, socket} =
        DawarichWeb.SettingsLive.Integrations.handle_params(params, state["path"], socket)

      html = render_component(&DawarichWeb.SettingsLive.Integrations.render/1, socket.assigns)
      rails = File.read!(Path.rootname(file) <> ".html")
      name = Path.basename(file, ".json")
      ids = LazyHTML.from_fragment(html) |> LazyHTML.query("[id]") |> LazyHTML.attribute("id")
      assert Enum.uniq(ids) == ids, name <> ": SVG and form ids must be unique"

      for [reference] <-
            Regex.scan(~r/(?:url\(["']?#|href="#)([^)"'\s]+)/, html, capture: :all_but_first) do
        assert reference in ids, name <> ": local SVG and fragment references must resolve"
      end

      Dawarich.Test.SettingsParity.dump(name, rails, html)

      html =
        String.replace(
          html,
          ~r/native-integration-(?:nav|pane)-(?:immich|photoprism|airtrail)-/,
          ""
        )

      for key <-
            ~w(immich_api_key photoprism_api_key airtrail_api_key teslamate_password teslamate_api_token),
          value = state["user"]["settings"][key],
          is_binary(value) and value != "" do
        refute html =~ value
        refute inspect(socket.assigns, limit: :infinity) =~ value
      end

      rails =
        Regex.replace(~r/<input\b[^>]*\btype="password"[^>]*>/, rails, fn input ->
          Regex.replace(~r/ value="[^"]+"/, input, " value=\"********\"")
        end)

      rails = Regex.replace(~r/ onchange="[^"]*"/, rails, "")
      actual = Dawarich.Test.ParityHTML.normalize(html)
      expected = Dawarich.Test.ParityHTML.normalize(rails)

      assert actual == expected,
             name <> ": " <> Dawarich.Test.ParityHTML.first_difference(actual, expected)
    end
  end

  @tag :d5_trek_selection
  test "TREK selection matches dated, archived and undated Rails trip rows in English and German" do
    for file <- Path.wildcard("test/fixtures/settings/trek_selection_*.json") do
      state = file |> File.read!() |> Jason.decode!()
      locale = state["user"]["settings"]["locale"]

      assigns = %{
        locale: locale,
        source: %{id: hd(state["trip_sources"])["id"]},
        rails_csrf_token: "CSRF",
        trips: state["remote_trips"],
        selected: state["selected"],
        loading: false,
        form: Phoenix.Component.to_form(%{}, as: :selection)
      }

      html = render_component(&DawarichWeb.TrekSelection.native_form/1, assigns)
      ids = LazyHTML.from_fragment(html) |> LazyHTML.query("[id]") |> LazyHTML.attribute("id")
      assert Enum.uniq(ids) == ids
      rails = File.read!(Path.rootname(file) <> ".html")
      Dawarich.Test.SettingsParity.dump(Path.basename(file, ".json"), rails, html)

      expected =
        rails |> String.replace(" id=\"trip_ids_\"", "") |> Dawarich.Test.ParityHTML.normalize()

      actual = Dawarich.Test.ParityHTML.normalize(html)
      assert actual == expected, Dawarich.Test.ParityHTML.first_difference(actual, expected)
    end
  end

  @tag :d5_account
  test "account profile, plans, credential slots and data dialogs match Rails 1.16.0" do
    files = Path.wildcard("test/fixtures/settings/account_*.json")
    assert length(files) == 11
    System.put_env("MANAGER_URL", "")

    for file <- files do
      Dawarich.FixtureCleanup.delete!(Repo, ~w(trip_sources stats users))
      state = file |> File.read!() |> Jason.decode!()
      user = seed!(state)
      principal = Dawarich.Accounts.Principal.project(user)
      {:ok, now, 0} = DateTime.from_iso8601(state["now"])
      locale = DawarichWeb.Locale.resolve(nil, user, %{})

      context = %{
        current_user: principal,
        current_scope: Dawarich.Accounts.Scope.for_user(principal, locale),
        locale: locale,
        self_hosted: state["self_hosted"],
        now: now,
        rails_csrf_token: "CSRF",
        base_url: "http://www.example.com"
      }

      {:ok, socket} =
        DawarichWeb.AccountLive.Edit.mount(%{}, %{}, %Phoenix.LiveView.Socket{
          endpoint: DawarichWeb.Endpoint,
          assigns: Map.put(context, :__changed__, %{})
        })

      html = render_component(&DawarichWeb.AccountLive.Edit.render/1, socket.assigns)
      refute html =~ state["user"]["api_key"]
      refute inspect(socket.assigns, limit: :infinity) =~ state["user"]["api_key"]
      assert html =~ "phx-hook=\"CredentialQr\""
      assert html =~ "data-auto-reveal=\"true\""
      assert html =~ "data-native-selection"

      assert LazyHTML.attribute(
               LazyHTML.query(LazyHTML.from_fragment(html), "#native-rotate-api-key"),
               "href"
             ) == ["#"]

      assert LazyHTML.attribute(
               LazyHTML.query(LazyHTML.from_fragment(html), "#native-export-data"),
               "href"
             ) == ["#"]

      rails = File.read!(Path.rootname(file) <> ".html")
      Dawarich.Test.SettingsParity.dump(Path.basename(file, ".json"), rails, html)
      actual = Dawarich.Test.AccountParity.normalize(html, state["user"]["api_key"])
      expected = Dawarich.Test.AccountParity.normalize(rails, state["user"]["api_key"])

      assert actual == expected,
             Path.basename(file) <>
               ": " <> Dawarich.Test.ParityHTML.first_difference(actual, expected)
    end
  end

  defp factor_dom(html) do
    html
    |> String.replace(~r/\sdata-auth-(?:form|settings-navigation)(?:="[^"]*")?/, "")
    |> String.replace(" focus-visible:outline focus-visible:outline-2", "")
    |> String.replace(" aria-current=\"page\"", "")
    |> Dawarich.Test.ParityHTML.normalize()
  end

  @fixtures Path.wildcard("test/fixtures/settings/insights_*.json")
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
