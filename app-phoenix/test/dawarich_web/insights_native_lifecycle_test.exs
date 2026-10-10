defmodule DawarichWeb.InsightsNativeLifecycleTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Dawarich.Test.StatsSeeds
  alias Dawarich.Test.NativeAdminUI
  alias DawarichWeb.InsightsLive.NativePage
  @endpoint DawarichWeb.Endpoint

  setup do
    %{target: user} = NativeAdminUI.setup!()
    stat!(user.id, %{year: 2024, month: 3, distance: 1000, daily_distance: [[1, 1000]]})
    stat!(user.id, %{year: 2025, month: 3, distance: 3000, daily_distance: [[1, 3000]]})
    on_exit(fn -> Application.delete_env(:dawarich, :native_insights_readers) end)
    old = System.get_env("JWT_SECRET_KEY")
    System.put_env("JWT_SECRET_KEY", "synthetic-insights-upgrade")

    on_exit(fn ->
      if old, do: System.put_env("JWT_SECRET_KEY", old), else: System.delete_env("JWT_SECRET_KEY")
    end)

    %{user: user}
  end

  for {name, params} <- [
        {"list period", %{"period" => []}},
        {"map year", %{"period" => %{"year" => %{}}}},
        {"map month", %{"period" => %{"month" => %{}}}}
      ] do
    @tag malformed_native_event: true
    test "Insights rejects #{name} events in place without losing reads or publishing refresh", %{
      user: user
    } do
      paused_readers()
      {:ok, view, _} = live(NativeAdminUI.conn(user), "/insights?year=2025&month=3")
      before = :sys.get_state(view.pid).socket
      fields = [:data, :query, :details, :residency, :refresh_state]

      {html, queries} =
        NativeAdminUI.queries(fn ->
          render_hook(view, "period", unquote(Macro.escape(params)))
        end)

      assert is_binary(html)
      assert Process.alive?(view.pid)
      after_event = :sys.get_state(view.pid).socket
      assert Map.take(after_event.assigns, fields) == Map.take(before.assigns, fields)
      assert after_event.private.data_async == before.private.data_async
      assert after_event.assigns.flash["alert"]
      assert queries != []
      refute Enum.any?(queries, &String.match?(&1, ~r/\A\s*(INSERT|UPDATE|DELETE)\b/i))
      render_click(view, "period", %{"period" => %{"year" => "2024", "month" => "3"}})
      assert :sys.get_state(view.pid).socket.assigns.data.year == 2024
    end
  end

  test "rapid Insights year and month patches drop stale details and residency results", %{
    user: user
  } do
    pid = self()

    reader = fn _scope, {params, _opts} ->
      send(pid, {:reading, self(), params})

      receive do
        :release -> {:ok, %{sentinel: "obsolete"}}
      end
    end

    Application.put_env(:dawarich, :native_insights_readers, %{details: reader, residency: reader})

    {:ok, view, _} = live(NativeAdminUI.conn(user), "/insights?year=2024&month=3")
    assert_receive {:reading, _, %{"year" => "2024", "month" => "3"}}
    old = :sys.get_state(view.pid).socket.private.data_async.runs
    render_patch(view, "/insights?year=2025&month=4")
    assert_receive {:reading, _, %{"year" => "2025", "month" => "4"}}
    socket = :sys.get_state(view.pid).socket

    for kind <- [:details, :residency] do
      {:noreply, result} =
        apply(NativePage, :handle_async, [
          old[kind].run,
          {:ok, {:ok, %{sentinel: "obsolete"}}},
          socket
        ])

      assert result.assigns[kind] == socket.assigns[kind]
      assert result.private.data_async.runs[kind].run == socket.private.data_async.runs[kind].run
    end

    assert socket.assigns.data.year == 2025
    assert socket.assigns.data.selected_month == 4
    refute NativeAdminUI.html(view) =~ "obsolete"
  end

  test "stale Insights delivery after replacement and policy change preserves current state", %{
    user: user
  } do
    paused_readers()
    {:ok, view, _} = live(NativeAdminUI.conn(user), "/insights?year=2024")
    old = :sys.get_state(view.pid).socket.private.data_async.runs.details.run
    render_patch(view, "/insights?year=2025")
    socket = :sys.get_state(view.pid).socket

    Dawarich.Repo.query!(
      "UPDATE users SET settings=$1 WHERE id=$2",
      [%{"timezone" => "Europe/Berlin"}, user.id],
      log: false
    )

    for result <- [{:ok, {:ok, %{state: :ready, sentinel: "obsolete"}}}, {:exit, :obsolete}] do
      assert {:noreply, returned} = NativePage.handle_async(old, result, socket)
      assert returned.private.data_async == socket.private.data_async

      assert Map.take(returned.assigns, [:data, :details, :residency, :flash, :refresh_state]) ==
               Map.take(socket.assigns, [:data, :details, :residency, :flash, :refresh_state])
    end

    current = socket.private.data_async.runs.details.run

    assert {:noreply, changed} =
             NativePage.handle_async(current, {:ok, {:ok, %{state: :ready}}}, socket)

    assert changed.assigns.data.period.zone == "Europe/Berlin"
    assert changed.private.data_async.generation > socket.private.data_async.generation
  end

  test "late Insights delivery after overview failure preserves absent ready data", %{user: user} do
    paused_readers()
    {:ok, view, _} = live(NativeAdminUI.conn(user), "/insights?year=2024")
    socket = :sys.get_state(view.pid).socket
    old = socket.private.data_async.runs.details.run
    assert {:noreply, failed} = NativePage.handle_params(%{"year" => []}, "", socket)
    assert failed.assigns.data == nil
    failed = Phoenix.Component.assign(failed, :query, %{"year" => "2025"})
    {replacement, failed} = DawarichWeb.DataAsync.register(failed, :details, "replacement")

    assert {:noreply, returned} =
             NativePage.handle_async(old, {:ok, {:ok, %{state: :ready}}}, failed)

    assert returned == failed

    assert {:noreply, absent} =
             NativePage.handle_async(replacement, {:ok, {:ok, %{state: :ready}}}, failed)

    assert absent.assigns.data == nil
    assert absent.private.data_async == failed.private.data_async
    DawarichWeb.DataAsync.cancel_all(failed)
  end

  defp paused_readers do
    Process.flag(:trap_exit, true)

    reader = fn _, _ ->
      receive do
        :release -> {:error, :unavailable}
      end
    end

    Application.put_env(:dawarich, :native_insights_readers, %{details: reader, residency: reader})
  end

  test "old timeout cannot fail retried Insights read", %{user: user} do
    reader = fn _, _ ->
      receive do
        :release -> {:error, :unavailable}
      end
    end

    Application.put_env(:dawarich, :native_insights_readers, %{details: reader, residency: reader})

    {:ok, view, _} = live(NativeAdminUI.conn(user), "/insights?year=2025")
    old = :sys.get_state(view.pid).socket.private.data_async.runs.details.run
    send(view.pid, {:data_read_timeout, old})
    assert has_element?(view, "#insights-details-error[role=alert]")
    render_click(view, "retry_read", %{"kind" => "details"})
    current = :sys.get_state(view.pid).socket.private.data_async.runs.details.run
    refute current == old
    send(view.pid, {:data_read_timeout, old})
    assert has_element?(view, "#insights-details-loading[role=status]")
    assert :sys.get_state(view.pid).socket.private.data_async.runs.details.run == current
  end

  test "reconnect reads a finished refresh without generating again", %{user: user} do
    {:ok, view, _} = live(NativeAdminUI.conn(user), "/insights?year=2025&month=3")
    render_async(view, 5000)
    assert has_element?(view, "#insights-refresh-pending[role=status]")

    [[args]] =
      Dawarich.Repo.query!(
        "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Stats.PageRefreshWorker'",
        [],
        log: false
      ).rows

    assert Dawarich.Repo.query!("SELECT id FROM digests WHERE user_id=$1", [user.id], log: false).rows ==
             []

    assert :ok = Dawarich.Stats.PageRefreshWorker.run(args, repo: Dawarich.Repo)
    render_async(view, 5000)
    assert has_element?(view, "#insights-details-ready")
    {:ok, reconnected, _} = live(NativeAdminUI.conn(user), "/insights?year=2025&month=3")
    render_async(reconnected, 5000)
    assert has_element?(reconnected, "#insights-details-ready")

    assert Dawarich.Repo.query!(
             "SELECT count(*) FROM oban.oban_jobs WHERE worker='Dawarich.Stats.PageRefreshWorker'",
             [],
             log: false
           ).rows == [[1]]
  end

  test "direct details and all-time preserve access and source values", %{user: user} do
    System.put_env("SELF_HOSTED", "false")
    {:ok, view, _} = live(NativeAdminUI.conn(user), "/insights/details?year=all")
    render_async(view, 5000)
    assert :sys.get_state(view.pid).socket.assigns.details.value.totals.distance == 4
    assert :sys.get_state(view.pid).socket.assigns.details.value.all_time
    refute has_element?(view, "#insights-residency-ready")
    refute NativeAdminUI.html(view) =~ "turbo-frame"
    refute NativeAdminUI.html(view) =~ "Chartkick"
    refute NativeAdminUI.html(view) =~ "data-controller"
    System.put_env("SELF_HOSTED", "false")
    Dawarich.Repo.query!("UPDATE users SET plan=0 WHERE id=$1", [user.id], log: false)
    render_patch(view, "/insights/details?year=2024")
    render_async(view, 5000)
    assert has_element?(view, "#insights-locked[role=status]")
    assert :sys.get_state(view.pid).socket.private.data_async.runs == %{}
  end

  test "Insights delivery re-admits changed identity and keeps retained state secret free", %{
    user: user
  } do
    {:ok, view, _} = live(NativeAdminUI.conn(user), "/insights?year=2025")
    render_async(view, 5000)
    raw = :erlang.term_to_binary(:sys.get_state(view.pid).socket.assigns)
    refute raw =~ user.api_key
    refute raw =~ user.encrypted_password

    Dawarich.Repo.query!(
      "UPDATE users SET encrypted_password='new-original-identity-00000000000000' WHERE id=$1",
      [user.id],
      log: false
    )

    send(view.pid, {:analytics_ready, user.id, "safe-revision"})
    assert_redirect(view, "/users/sign_in")
  end

  test "native Insights ready monthly cards retain first visits locations comparisons and chart values",
       %{user: user} do
    stamp = NaiveDateTime.utc_now(:second) |> NaiveDateTime.add(10)

    digest!(user.id, %{
      year: 2025,
      distance: 3000,
      updated_at: stamp,
      travel_patterns: %{
        "time_of_day" => %{"morning" => 100},
        "activity_breakdown" => %{"walking" => %{"duration" => 60, "percentage" => 100}},
        "seasonality" => %{"spring" => 100}
      }
    })

    digest!(user.id, %{
      year: 2025,
      month: 3,
      period_type: 0,
      distance: 3000,
      updated_at: stamp,
      monthly_distances: %{"1" => 3000},
      first_time_visits: %{"countries" => ["Germany"], "cities" => ["Berlin"]},
      toponyms: [
        %{
          "country" => "Germany",
          "cities" => [
            %{"city" => "Berlin", "stayed_for" => 60, "api_key" => "synthetic-hidden-city-key"}
          ]
        }
      ],
      year_over_year: %{"distance_change_percent" => 50, "countries_change" => 1}
    })

    {:ok, view, _} = live(NativeAdminUI.conn(user), "/insights?year=2025&month=3")
    render_async(view, 5000)
    html = NativeAdminUI.html(view)
    assert html =~ "Berlin"
    assert html =~ "Germany"
    assert html =~ "+50%"
    assert has_element?(view, "#insights-monthly-chart[phx-hook=NativeChart]")

    [raw] =
      html
      |> LazyHTML.from_document()
      |> LazyHTML.query("#insights-monthly-chart")
      |> LazyHTML.attribute("data-chart")

    assert Enum.map(Jason.decode!(raw)["data"], &List.last/1) |> Enum.sum() == 3
    refute html =~ "synthetic-hidden-city-key"

    refute :erlang.term_to_binary(:sys.get_state(view.pid).socket.assigns) =~
             "synthetic-hidden-city-key"

    assert NativeAdminUI.labels(html) == []
  end

  test "late Insights delivery clears patterns after eligibility changes", %{user: user} do
    System.put_env("SELF_HOSTED", "false")
    owner = self()

    reader = fn _, _ ->
      send(owner, {:paused, self()})

      receive do
        :release -> {:ok, %{state: :ready, secret_pattern: "obsolete"}}
      end
    end

    Application.put_env(:dawarich, :native_insights_readers, %{details: reader, residency: reader})

    {:ok, view, _} = live(NativeAdminUI.conn(user), "/insights?year=2025")
    assert_receive {:paused, one}
    assert_receive {:paused, two}
    Dawarich.Repo.query!("UPDATE users SET plan=0 WHERE id=$1", [user.id], log: false)
    send(one, :release)
    send(two, :release)
    render_async(view, 5000)
    result = :sys.get_state(view.pid).socket
    assert result.assigns.data.restricted
    assert result.assigns.details.state == :restricted
    refute :erlang.term_to_binary(result.assigns) =~ "obsolete"
    assert result.private.data_async.runs == %{}
  end
end
