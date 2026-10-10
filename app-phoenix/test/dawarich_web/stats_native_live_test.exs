defmodule DawarichWeb.StatsNativeLiveTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Dawarich.Test.StatsSeeds
  alias Dawarich.Test.NativeAdminUI
  alias Dawarich.Accounts.Scope
  @endpoint DawarichWeb.Endpoint

  setup do
    %{target: user} = NativeAdminUI.setup!()
    stat!(user.id, %{year: 2024, month: 3, distance: 1000, daily_distance: [[1, 1000]]})

    stat!(user.id, %{year: 2025, month: 3, distance: 3000, daily_distance: [[1, 1000], [2, 2000]]})

    stat!(user.id, %{year: 2025, month: 4, distance: 9000, daily_distance: [[1, 9000]]})
    %{user: user}
  end

  test "stats year patches change data and survive browser history", %{user: user} do
    {:ok, view, _html} = live(NativeAdminUI.conn(user), "/stats/2025")
    assert has_element?(view, "#stats-native-chart")
    assert :sys.get_state(view.pid).socket.assigns.data.year == 2025
    render_patch(view, "/stats/2024")
    assert :sys.get_state(view.pid).socket.assigns.data.distances |> Enum.sum() == 1000
    render_patch(view, "/stats/2025")
    assert :sys.get_state(view.pid).socket.assigns.data.distances |> Enum.sum() == 12000
    html = NativeAdminUI.html(view)
    refute html =~ "data-controller"
    refute html =~ "turbo-frame"
    refute html =~ "data-turbo"
    assert NativeAdminUI.labels(html) == []
    refute :erlang.term_to_binary(:sys.get_state(view.pid).socket.assigns) =~ user.api_key

    refute :erlang.term_to_binary(:sys.get_state(view.pid).socket.assigns) =~
             user.encrypted_password
  end

  test "stats month slice preserves local peak-day link and previous-month average", %{user: user} do
    Dawarich.Repo.query!(
      "UPDATE users SET settings=$2 WHERE id=$1",
      [user.id, %{"timezone" => "Pacific/Kiritimati"}],
      log: false
    )

    scope = Scope.for_user(user, "de")

    assigns = %{
      __changed__: %{},
      locale: "de",
      now: ~U[2026-02-28 23:30:00Z],
      self_hosted: true,
      live_action: :month,
      flash: %{},
      base_url: "http://www.example.com"
    }

    socket = %Phoenix.LiveView.Socket{
      assigns: assigns,
      private: %{data_principal: Dawarich.NativeM5.Dependencies.principal(scope)}
    }

    {:ok, socket} = apply(DawarichWeb.StatsLive.NativePage, :mount, [%{}, %{}, socket])

    {:noreply, socket} =
      apply(DawarichWeb.StatsLive.NativePage, :handle_params, [
        %{"year" => "2025", "month" => "4"},
        "http://www.example.com/stats/2025/4",
        socket
      ])

    assert socket.assigns.data.data.previous.distance == 3000
    assert socket.assigns.data.data.average_km == 6
    assert elem(socket.assigns.data.bounds, 0) == "2025-04-01 00:00:00 +1400"
    html = DawarichWeb.StatsLive.NativePage.render(socket.assigns) |> rendered_to_string()
    assert html =~ "/map/v2?"
    assert html =~ URI.encode_query(%{"start_at" => "2025-04-01 00:00:00 +1400"})

    {:noreply, socket} =
      DawarichWeb.StatsLive.NativePage.handle_params(
        %{"year" => "2025", "month" => "3"},
        "http://www.example.com/stats/2025/3",
        socket
      )

    assert socket.assigns.data.peak == {2, 2000}
    assert socket.assigns.data.month == 3
  end

  test "stats update and share refuse stale eligibility with no publication", %{user: user} do
    {:ok, view, _} = live(NativeAdminUI.conn(user), "/stats")
    view |> element("#stats-update") |> render_click()
    view |> element("#stats-update") |> render_click()

    assert Dawarich.Repo.query!(
             "SELECT count(*) FROM job_outbox WHERE command_type='stats.full_recalculation'",
             [],
             log: false
           ).rows == [[1]]

    Dawarich.Repo.query!(
      "UPDATE users SET active_until=$2 WHERE id=$1",
      [user.id, ~U[2000-01-01 00:00:00Z]],
      log: false
    )

    html = render_click(view, "update", %{})
    assert html =~ NativeAdminUI.escaped("controllers.application.admin_action_failed")

    assert Dawarich.Repo.query!(
             "SELECT count(*) FROM job_outbox WHERE command_type='stats.full_recalculation'",
             [],
             log: false
           ).rows == [[1]]

    scope = Scope.for_user(user, "en")

    assert {:error, :unauthorized} =
             apply(Dawarich.Stats.Commands, :share, [
               scope,
               %{"year" => "2025", "month" => "3"},
               %{"enabled" => "1", "expiration" => "12h"},
               [self_hosted: true]
             ])

    assert Dawarich.Repo.query!(
             "SELECT sharing_uuid FROM stats WHERE user_id=$1 AND year=2025 AND month=3",
             [user.id],
             log: false
           ).rows == [[nil]]
  end

  test "cold count renders pending without double calculation", %{user: user} do
    {:ok, view, _html} = live(NativeAdminUI.conn(user), "/stats")
    assert has_element?(view, "#stats-count-pending[role=status]")
    assert :sys.get_state(view.pid).socket.assigns.data.total_distance == 13000

    assert Dawarich.Repo.query!(
             "SELECT user_id FROM phoenix.stats_point_counts WHERE user_id=$1",
             [user.id],
             log: false
           ).rows == []

    assert Dawarich.Repo.query!(
             "SELECT count(*) FROM oban.oban_jobs WHERE worker='Dawarich.Stats.PageRefreshWorker'",
             [],
             log: false
           ).rows == [[1]]

    {_, queries} = NativeAdminUI.queries(fn -> NativeAdminUI.html(view) end)
    assert queries == []
    refute Enum.any?(queries, &String.contains?(&1, "count(*) FROM points"))
    assert :sys.get_state(view.pid).socket.assigns.data.points.state == :pending
  end

  test "native Stats retains localized source totals places and refresh completion", %{user: user} do
    Dawarich.Repo.query!(
      "UPDATE stats SET toponyms=$2 WHERE user_id=$1 AND year=2025 AND month=3",
      [user.id, [%{"country" => "Germany", "cities" => [%{"city" => "Berlin"}]}]],
      log: false
    )

    {:ok, view, _} = live(NativeAdminUI.conn(user), "/stats?locale=de")
    assert has_element?(view, "#stats-year-total-2025", "12 km")
    assert has_element?(view, "#stats-year-places-2025", "1")
    view |> element("button[phx-value-kind=countries]") |> render_click()
    assert has_element?(view, "#stats-dialog li", "Germany")
    render_click(view, "close_dialog", %{})
    view |> element("button[phx-value-kind=cities]") |> render_click()
    assert has_element?(view, "#stats-dialog li", "Berlin")
    assert Dawarich.Test.NativeAdminUI.labels(NativeAdminUI.html(view)) == []

    [[args]] =
      Dawarich.Repo.query!(
        "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Stats.PageRefreshWorker'",
        [],
        log: false
      ).rows

    assert :ok = Dawarich.Stats.PageRefreshWorker.run(args, repo: Dawarich.Repo)
    assert has_element?(view, "#stats-count-ready")
    refute has_element?(view, "#stats-count-pending")
    {:ok, year, _} = live(NativeAdminUI.conn(user), "/stats/2025?locale=de")
    assert has_element?(year, "#stats-native-chart", "März")
    assert has_element?(year, "#stats-month-places-3", "Berlin")
    assert has_element?(year, "a[href='/stats/2025/3']", "März")
    assert NativeAdminUI.html(year) =~ "Statistics" or NativeAdminUI.html(year) =~ "Statistiken"
  end

  test "stats period commands publish once per selection and sharing keeps source expiration", %{
    user: user
  } do
    {:ok, view, _} = live(NativeAdminUI.conn(user), "/stats/2025")
    render_click(view, "update", %{})
    render_click(view, "update", %{})

    assert Dawarich.Repo.query!(
             "SELECT count(*) FROM oban.oban_jobs WHERE worker='Dawarich.Stats.CalculateMonthWorker'",
             [],
             log: false
           ).rows == [[12]]

    render_patch(view, "/stats/2024")
    render_click(view, "update", %{})

    assert Dawarich.Repo.query!(
             "SELECT count(*) FROM oban.oban_jobs WHERE worker='Dawarich.Stats.CalculateMonthWorker'",
             [],
             log: false
           ).rows == [[24]]

    scope = Scope.for_user(user, "en")
    params = %{"year" => "2025", "month" => "3"}

    assert {:ok, sharing} =
             Dawarich.Stats.Commands.share(
               scope,
               params,
               %{"enabled" => "1", "expiration" => "12h"},
               now: ~U[2026-10-01 12:00:00Z],
               self_hosted: true,
               base_url: "https://example.invalid"
             )

    assert sharing.url =~ "https://example.invalid/shared/month/"
    assert sharing.enabled
    assert {:ok, expiry, _} = DateTime.from_iso8601(sharing.expires_at)
    assert expiry == ~U[2026-10-02 00:00:00Z]

    assert {:ok, %{enabled: false, url: ""}} =
             Dawarich.Stats.Commands.share(
               scope,
               params,
               %{"enabled" => "0", "expiration" => "12h"},
               self_hosted: true
             )

    Dawarich.Repo.query!("UPDATE users SET plan=0 WHERE id=$1", [user.id], log: false)

    assert {:error, :unauthorized} =
             Dawarich.Stats.Commands.share(
               scope,
               params,
               %{"enabled" => "1", "expiration" => "1h"},
               self_hosted: false
             )
  end

  test "native Stats Lite upgrades are generated on action while page state stays credential free",
       %{user: user} do
    System.put_env("SELF_HOSTED", "false")
    System.put_env("JWT_SECRET_KEY", "synthetic-native-stats-upgrade-secret")
    on_exit(fn -> System.delete_env("JWT_SECRET_KEY") end)
    Dawarich.Repo.query!("UPDATE users SET plan=0 WHERE id=$1", [user.id], log: false)
    {:ok, view, _} = live(NativeAdminUI.conn(user), "/stats")
    assert has_element?(view, "#stats-window-alert[role=alert]")
    assert has_element?(view, "#stats-locked-2024")
    assert has_element?(view, "button[phx-click=upgrade]")
    raw = :erlang.term_to_binary(:sys.get_state(view.pid).socket.assigns)
    refute raw =~ "token="
    refute raw =~ user.api_key
    view |> element("#stats-upgrade") |> render_click()
    {path, _flash} = assert_redirect(view)
    assert URI.decode_query(URI.parse(path).query)["utm_medium"] == "data_window"
  end

  test "normalized stats recalculation receipts suppress equivalent source casts", %{user: user} do
    scope = Scope.for_user(user, "en")
    receipt = Ecto.UUID.generate()

    assert {:ok, _} =
             Dawarich.Stats.Commands.update(
               scope,
               %{"year" => "2025tail", "month" => "03"},
               receipt,
               self_hosted: true
             )

    assert {:ok, _} =
             Dawarich.Stats.Commands.update(scope, %{"year" => "2025", "month" => "3"}, receipt,
               self_hosted: true
             )

    assert Dawarich.Repo.query!(
             "SELECT count(*) FROM oban.oban_jobs WHERE worker='Dawarich.Stats.CalculateMonthWorker'",
             [],
             log: false
           ).rows == [[1]]

    assert {:error, :invalid_input} =
             Dawarich.Stats.Commands.update(
               scope,
               %{"year" => "2025", "month" => "3tail"},
               Ecto.UUID.generate(),
               self_hosted: true
             )
  end

  test "native month slice retains source activity comparisons flight and empty states", %{
    user: user
  } do
    Dawarich.Repo.query!(
      "UPDATE stats SET flight_distance=5000,toponyms=$2 WHERE user_id=$1 AND year=2025 AND month=4",
      [user.id, [%{"country" => "Germany", "cities" => [%{"city" => "Berlin"}]}]],
      log: false
    )

    scope = Scope.for_user(user, "en")

    {:ok, data} =
      Dawarich.Stats.Pages.month(scope, %{"year" => "2025", "month" => "4"}, self_hosted: true)

    html =
      render_component(&DawarichWeb.StatsLive.NativeMonthParts.summary/1,
        data: data,
        locale: "en"
      )

    assert html =~ "1/1"
    assert html =~ "50% more than your average"
    assert html =~ "1 day less than previous month"
    assert html =~ "5 km"
    assert html =~ "Berlin"

    {:ok, empty} =
      Dawarich.Stats.Pages.month(scope, %{"year" => "2025", "month" => "2"}, self_hosted: true)

    html =
      render_component(&DawarichWeb.StatsLive.NativeMonthParts.summary/1,
        data: empty,
        locale: "en"
      )

    assert html =~ "No location data available for this month"
  end

  test "Stats places retain full totals beyond the dialog window", %{user: user} do
    places = for n <- 1..61, do: %{"city" => "City #{n}"}

    Dawarich.Repo.query!(
      "UPDATE stats SET toponyms=$2 WHERE user_id=$1",
      [user.id, [%{"country" => "Germany", "cities" => places}]],
      log: false
    )

    {:ok, view, _} = live(NativeAdminUI.conn(user), "/stats")
    assert has_element?(view, "button[phx-value-kind=cities]", "61")
    render_click(view, "open_places", %{"kind" => "cities"})

    assert Enum.count(
             NativeAdminUI.html(view)
             |> LazyHTML.from_document()
             |> LazyHTML.query("#stats-dialog li")
           ) == 50

    render_patch(view, "/stats?places_kind=cities&places_page=2")

    assert Enum.count(
             NativeAdminUI.html(view)
             |> LazyHTML.from_document()
             |> LazyHTML.query("#stats-dialog li")
           ) == 11

    assert has_element?(view, "button[phx-value-kind=cities]", "61")
  end

  test "Stats sharing dialog retains disabled state expiration and second-tab changes", %{
    user: user
  } do
    scope = Scope.for_user(user, "en")
    params = %{"year" => "2025", "month" => "3"}

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        locale: "en",
        self_hosted: true,
        live_action: :month,
        flash: %{},
        base_url: "https://example.invalid"
      },
      private: %{data_principal: Dawarich.NativeM5.Dependencies.principal(scope)}
    }

    {:ok, socket} = DawarichWeb.StatsLive.NativePage.mount(%{}, %{}, socket)
    {:noreply, socket} = DawarichWeb.StatsLive.NativePage.handle_params(params, "", socket)

    for expiration <- ["12h", "24h"] do
      assert {:ok, _} =
               Dawarich.Stats.Commands.share(
                 scope,
                 params,
                 %{"enabled" => "1", "expiration" => expiration},
                 self_hosted: true
               )

      {:noreply, opened} =
        DawarichWeb.StatsLive.NativePage.handle_event("open_share", %{}, socket)

      assert_share_fields(opened, true, expiration)

      {:noreply, socket} =
        DawarichWeb.StatsLive.NativePage.handle_event("close_dialog", %{}, opened)

      assert socket.assigns.stats_dialog == nil
    end

    {:noreply, opened} = DawarichWeb.StatsLive.NativePage.handle_event("open_share", %{}, socket)

    {:noreply, disabled} =
      DawarichWeb.StatsLive.NativePage.handle_event(
        "share",
        %{"enabled" => "0", "expiration" => "24h"},
        opened
      )

    assert_share_fields(disabled, false, "24h")

    {:noreply, closed} =
      DawarichWeb.StatsLive.NativePage.handle_event("close_dialog", %{}, disabled)

    {:noreply, reopened} =
      DawarichWeb.StatsLive.NativePage.handle_event("open_share", %{}, closed)

    assert_share_fields(reopened, false, "24h")
  end

  defp assert_share_fields(socket, enabled, expiration) do
    html =
      DawarichWeb.StatsLive.NativePage.render(socket.assigns)
      |> rendered_to_string()
      |> LazyHTML.from_document()

    assert not Enum.empty?(LazyHTML.query(html, "#stats-sharing-enabled[checked]")) == enabled

    assert LazyHTML.query(html, "#stats-sharing-expiration option[selected]")
           |> LazyHTML.attribute("value") == [expiration]

    if not enabled, do: assert(Enum.empty?(LazyHTML.query(html, "#stats-sharing-url")))
  end

  test "Stats recalculation preserves source reload behavior without a dead completion subscription",
       %{user: user} do
    previous = Application.get_env(:dawarich, :jobs_repo)
    Application.put_env(:dawarich, :jobs_repo, Dawarich.Repo)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:dawarich, :jobs_repo, previous),
        else: Application.delete_env(:dawarich, :jobs_repo)
    end)

    {:ok, view, _} = live(NativeAdminUI.conn(user), "/stats/2025")
    refute Dawarich.Stats.PageRefresh.topic(user.id) in Registry.keys(Dawarich.PubSub, view.pid)
    before = :sys.get_state(view.pid).socket
    assert before.assigns.data.distances |> Enum.sum() == 12000
    render_click(view, "update", %{})

    [[id, args]] =
      Dawarich.Repo.query!(
        "SELECT id,args FROM oban.oban_jobs WHERE worker='Dawarich.Stats.CalculateMonthWorker' AND args->>'month'='3'",
        [],
        log: false
      ).rows

    assert :ok = Dawarich.Stats.CalculateMonthWorker.perform(%Oban.Job{id: id, args: args})

    assert Dawarich.Repo.query!(
             "SELECT distance FROM stats WHERE user_id=$1 AND year=2025 AND month=3",
             [user.id],
             log: false
           ).rows == [[0]]

    socket = :sys.get_state(view.pid).socket
    assert socket.assigns.data.distances |> Enum.sum() == 12000

    assert {:noreply, unchanged} =
             DawarichWeb.StatsLive.NativePage.handle_info(
               {:analytics_ready, user.id, "absent-protocol"},
               socket
             )

    assert unchanged == socket
    render_patch(view, "/stats/2025")
    assert :sys.get_state(view.pid).socket.assigns.data.distances |> Enum.sum() == 9000
  end

  @tag cache_return: true
  test "Stats cache delivery refuses a changed actor during SET before assigning its projection",
       %{user: user} do
    {:ok, view, _} = live(NativeAdminUI.conn(user), "/stats/2025")
    assert :sys.get_state(view.pid).socket.assigns.data.year == 2025
    {:ok, cache} = Dawarich.Test.NativePageCache.start()

    command = fn args ->
      result = Dawarich.Test.NativePageCache.command(cache, args)

      if hd(args) == "SET",
        do:
          Dawarich.Repo.query!(
            "UPDATE users SET encrypted_password='changed-synthetic-stats-identity' WHERE id=$1",
            [user.id],
            log: false
          )

      result
    end

    previous = Application.get_env(:dawarich, :native_page_cache_command)
    Application.put_env(:dawarich, :native_page_cache_command, command)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:dawarich, :native_page_cache_command, previous),
        else: Application.delete_env(:dawarich, :native_page_cache_command)
    end)

    assert {:error, {:redirect, %{to: "/users/sign_in"}}} = render_patch(view, "/stats/2024")
    assert Dawarich.Test.NativePageCache.entries(cache) == %{}
    assert Enum.any?(Dawarich.Test.NativePageCache.commands(cache), &match?(["SET" | _], &1))
  end

  @tag projection_refusal: true
  test "malformed Stats URL clears its places dialog and refuses data events without effects", %{
    user: user
  } do
    Process.flag(:trap_exit, true)
    {:ok, view, html} = live(NativeAdminUI.conn(user), "/stats?year[bad]=1&places_kind=countries")
    assert is_binary(html)
    assert Process.alive?(view.pid)
    assert :sys.get_state(view.pid).socket.assigns.data == nil
    assert :sys.get_state(view.pid).socket.assigns.stats_dialog == nil
    refute has_element?(view, "#stats-dialog")

    for {event, params} <- [
          {"open_places", %{"kind" => "countries"}},
          {"update", %{}},
          {"open_share", %{}},
          {"share", %{"enabled" => "1"}}
        ] do
      render_click(view, "lv:clear-flash", %{"key" => "alert"})
      {_, queries} = NativeAdminUI.queries(fn -> render_hook(view, event, params) end)
      socket = :sys.get_state(view.pid).socket
      assert socket.assigns.data == nil
      assert socket.assigns.stats_dialog == nil
      assert socket.assigns.flash["alert"]
      refute Enum.any?(queries, &String.match?(&1, ~r/\A\s*(INSERT|UPDATE|DELETE)\b/i))
    end

    render_patch(view, "/stats")
    assert :sys.get_state(view.pid).socket.assigns.data.total_distance == 13000
  end

  @tag projection_refusal: true
  test "Stats year URL and forged places event retain the year projection without an index dialog",
       %{user: user} do
    Process.flag(:trap_exit, true)
    {:ok, view, _} = live(NativeAdminUI.conn(user), "/stats/2025?places_kind=countries")
    before = :sys.get_state(view.pid).socket.assigns.data
    assert before.year == 2025
    refute has_element?(view, "#stats-dialog")
    render_hook(view, "open_places", %{"kind" => "countries"})
    socket = :sys.get_state(view.pid).socket
    assert socket.assigns.data == before
    assert socket.assigns.stats_dialog == nil
    assert socket.assigns.flash["alert"]
  end
end
