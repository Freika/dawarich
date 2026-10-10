defmodule DawarichWeb.BackgroundJobsLiveTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Admin.Background
  alias Dawarich.Test.NativeAdminUI
  @endpoint DawarichWeb.Endpoint

  setup do
    c = NativeAdminUI.setup!()
    previous = Application.get_env(:dawarich, Background)
    jobs_repo = Application.get_env(:dawarich, :jobs_repo)
    Dawarich.JobsCase.start_oban(BackgroundUIOban, repo: Repo)
    Application.put_env(:dawarich, Background, %{oban: BackgroundUIOban})
    Dawarich.Jobs.Ownership.put!(Repo, "command:geocoding.reverse_point", :oban)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:dawarich, Background, previous),
        else: Application.delete_env(:dawarich, Background)

      Application.put_env(:dawarich, :jobs_repo, jobs_repo)
    end)

    c
  end

  test "ordinary background mount and events never query job health", c do
    {conn, static} =
      NativeAdminUI.queries(fn ->
        get(NativeAdminUI.conn(c.target), "/settings/background_jobs")
      end)

    {{:ok, view, html}, connected} = NativeAdminUI.queries(fn -> live(conn) end)
    assert :sys.get_state(view.pid).socket.assigns.native
    assert :sys.get_state(view.pid).socket.assigns.health == nil
    refute html =~ "href=\"/sidekiq\""
    refute has_element?(view, "#phoenix-jobs")
    render_hook(view, "open_visits", %{})
    {_, event} = NativeAdminUI.queries(fn -> render_hook(view, "update_visits", %{}) end)

    for sql <- static ++ connected ++ event do
      refute sql =~ "to_regclass('phoenix.job_owners')"
      refute sql =~ "FROM job_outbox WHERE state"
    end

    IO.puts(
      "background ordinary queries static=#{length(static)} connected=#{length(connected)} event=#{length(event)}"
    )

    assert length(static) in 1..13
    assert length(connected) in 1..8
    assert NativeAdminUI.labels(html) == []
    GenServer.stop(view.pid)
  end

  test "visits toggle persists exact strings and survives reload with no queued jobs", c do
    {:ok, view, _} = live(NativeAdminUI.conn(c.target), "/settings/background_jobs")

    for expected <- ["false", "true", "false"] do
      before = Accounts.settings(c.target.id)["visits_suggestions_enabled"]
      view |> element("#visits-toggle") |> render_click()
      assert Accounts.settings(c.target.id)["visits_suggestions_enabled"] == before
      html = view |> element("#confirm-visits") |> render_click()
      assert Accounts.settings(c.target.id)["visits_suggestions_enabled"] == expected
      assert Accounts.settings(c.target.id)["timezone"] == "UTC"

      assert html =~
               NativeAdminUI.escaped("controllers.settings.background_jobs.settings_updated")

      {:ok, fresh, _} = live(NativeAdminUI.conn(c.target), "/settings/background_jobs")
      assert :sys.get_state(fresh.pid).socket.assigns.data.visits == (expected == "true")
      GenServer.stop(fresh.pid)
    end

    assert Repo.query!("SELECT count(*) FROM job_outbox").rows == [[0]]
    assert Repo.query!("SELECT count(*) FROM oban.oban_jobs").rows == [[0]]
  end

  test "reverse job event confirms and accepts once per page with correct force", c do
    {:ok, view, _} = live(NativeAdminUI.conn(c.target), "/settings/background_jobs")
    render_hook(view, "request_job", %{"name" => "start_reverse_geocoding"})
    assert Repo.query!("SELECT count(*) FROM oban.oban_jobs").rows == [[0]]

    for {job, force} <- [{"start_reverse_geocoding", true}, {"continue_reverse_geocoding", false}] do
      view |> element("#open-#{job}") |> render_click()
      html = view |> element("#confirm-background-job") |> render_click()

      assert html =~
               NativeAdminUI.escaped(
                 "controllers.settings.background_jobs.job_was_successfully_created"
               )

      assert_push_event(view, "close-dialog", %{id: "background-job-confirm"})
      render_hook(view, "open_job", %{"name" => job})
      render_hook(view, "request_job", %{})
      assert has_element?(view, "#open-#{job}[disabled]")

      assert [[1]] =
               Repo.query!(
                 "SELECT count(*) FROM oban.oban_jobs WHERE args->>'user_id'=$1 AND args->>'force'=$2",
                 [to_string(c.target.id), to_string(force)]
               ).rows
    end

    assert [[2]] = Repo.query!("SELECT count(*) FROM oban.oban_jobs").rows
  end

  test "background cancellation queues nothing and failed dispatch allows retry", c do
    {:ok, view, _} = live(NativeAdminUI.conn(c.target), "/settings/background_jobs")
    render_hook(view, "open_job", %{"name" => "start_reverse_geocoding"})
    view |> element("#cancel-background-job") |> render_click()
    render_hook(view, "open_visits", %{})
    view |> element("#cancel-visits") |> render_click()
    assert Accounts.settings(c.target.id)["visits_suggestions_enabled"] == nil
    assert :sys.get_state(view.pid).socket.assigns.pending_job == nil
    assert Repo.query!("SELECT count(*) FROM oban.oban_jobs").rows == [[0]]
    Dawarich.Jobs.Ownership.put!(Repo, "command:geocoding.reverse_point", :sidekiq)
    render_hook(view, "open_job", %{"name" => "start_reverse_geocoding"})

    assert render_hook(view, "request_job", %{}) =~
             NativeAdminUI.escaped("controllers.application.admin_action_failed")

    refute has_element?(view, "#open-start_reverse_geocoding[disabled]")
    Dawarich.Jobs.Ownership.put!(Repo, "command:geocoding.reverse_point", :oban)
    render_hook(view, "request_job", %{})
    assert Repo.query!("SELECT count(*) FROM oban.oban_jobs").rows == [[1]]
  end

  test "background stale password or deletion refuses every event and info response", c do
    for reason <- [:salt, :deletion],
        event <- [
          :update_visits,
          :request_job,
          :open_job,
          :open_visits,
          :cancel_visits,
          :cancel_job,
          :params,
          :info
        ] do
      Repo.query!(
        "UPDATE users SET deleted_at=NULL,encrypted_password=$2 WHERE id=$1",
        [c.target.id, c.target.encrypted_password],
        log: false
      )

      {:ok, view, _} = live(NativeAdminUI.conn(c.target), "/settings/background_jobs")
      render_hook(view, "open_job", %{"name" => "start_reverse_geocoding"})

      if reason == :salt,
        do:
          Repo.query!(
            "UPDATE users SET encrypted_password='synthetic-background-salt' WHERE id=$1",
            [c.target.id]
          ),
        else: Repo.query!("UPDATE users SET deleted_at=now() WHERE id=$1", [c.target.id])

      socket = :sys.get_state(view.pid).socket

      case event do
        :info ->
          assert {:halt, _} = Phoenix.LiveView.Lifecycle.handle_info(:navbar_refresh, socket)
          send(view.pid, :navbar_refresh)

        :params ->
          assert {:halt, _} =
                   Phoenix.LiveView.Lifecycle.handle_params(
                     %{},
                     "http://www.example.com/settings/background_jobs?section=jobs",
                     socket
                   )

          render_patch(view, "/settings/background_jobs?section=jobs")

        _ ->
          assert {:halt, _} =
                   Phoenix.LiveView.Lifecycle.handle_event(to_string(event), %{}, socket)

          render_hook(view, to_string(event), %{"name" => "start_reverse_geocoding"})
      end

      assert_redirect(view, "/users/sign_in")
      assert Repo.query!("SELECT count(*) FROM oban.oban_jobs").rows == [[0]]
    end
  end

  test "admin demotion clears populated health while retaining ordinary controls and bounded mounts",
       c do
    {sparse_conn, sparse_static} =
      NativeAdminUI.queries(fn ->
        get(NativeAdminUI.conn(c.actor), "/settings/background_jobs")
      end)

    {{:ok, sparse, _}, sparse_connected} = NativeAdminUI.queries(fn -> live(sparse_conn) end)

    IO.puts(
      "background admin sparse queries static=#{length(sparse_static)} connected=#{length(sparse_connected)}"
    )

    assert length(sparse_static) in 1..21
    assert length(sparse_connected) in 1..16
    GenServer.stop(sparse.pid)
    Application.put_env(:dawarich, :jobs_repo, Repo)

    Oban.insert!(
      BackgroundUIOban,
      Dawarich.Admin.BackgroundGeocodingWorker.new(%{
        "user_id" => c.target.id,
        "force" => false,
        "after_id" => 0,
        "locale" => "en"
      })
    )

    {conn, static} =
      NativeAdminUI.queries(fn ->
        get(NativeAdminUI.conn(c.actor), "/settings/background_jobs")
      end)

    {{:ok, view, html}, connected} = NativeAdminUI.queries(fn -> live(conn) end)
    assert :sys.get_state(view.pid).socket.assigns.native
    assert has_element?(view, "a[href='/sidekiq'][target='_blank']")
    assert has_element?(view, "#phoenix-jobs")
    assert html =~ "BackgroundGeocodingWorker"
    IO.puts("background admin queries static=#{length(static)} connected=#{length(connected)}")
    assert length(static) in 1..37
    assert length(connected) in 1..33
    Repo.query!("UPDATE users SET admin=false WHERE id=$1", [c.actor.id])
    render_hook(view, "update_visits", %{})
    assert :sys.get_state(view.pid).socket.assigns.health == nil
    refute has_element?(view, "#phoenix-jobs")
    refute has_element?(view, "a[href='/sidekiq']")
    assert has_element?(view, "#visits-toggle")
    assert Process.alive?(view.pid)
  end

  test "background source fixture values and pending GPS notice remain readable", c do
    for name <-
          ~w(default string_true string_false bool_true bool_false nil queued recalculated neither) do
      state = Jason.decode!(File.read!("test/fixtures/admin_pages/background_#{name}.json"))
      settings = state["user"]["settings"]
      Repo.query!("UPDATE users SET settings=$2 WHERE id=$1", [c.target.id, settings])
      {:ok, view, html} = live(NativeAdminUI.conn(c.target), "/settings/background_jobs")
      data = :sys.get_state(view.pid).socket.assigns.data

      assert data.visits ==
               (Map.get(settings || %{}, "visits_suggestions_enabled", "true") == "true")

      expected_notice =
        File.read!("test/fixtures/admin_pages/background_#{name}.html")
        |> String.contains?("gps-noise-recheck-pending")

      assert data.notice == expected_notice
      assert has_element?(view, "[data-testid=gps-noise-recheck-pending]") == expected_notice
      assert NativeAdminUI.labels(html) == []
      GenServer.stop(view.pid)
    end
  end

  test "OIDC refuses the visits toggle clearly and still dispatches background jobs", c do
    previous = Application.get_env(:dawarich, Background)

    Application.put_env(:dawarich, Background, %{
      oban: BackgroundUIOban,
      env: %{
        "SELF_HOSTED" => "true",
        "OIDC_CLIENT_ID" => "synthetic",
        "OIDC_CLIENT_SECRET" => "synthetic"
      }
    })

    {:ok, view, _} = live(NativeAdminUI.conn(c.target), "/settings/background_jobs")
    alert = NativeAdminUI.escaped("controllers.application.admin_writes_unavailable_with_oidc")
    render_hook(view, "open_job", %{"name" => "start_reverse_geocoding"})
    refute render_hook(view, "request_job", %{}) =~ alert
    assert Repo.query!("SELECT count(*) FROM oban.oban_jobs").rows == [[1]]
    render_hook(view, "open_visits", %{})
    assert render_hook(view, "update_visits", %{}) =~ alert
    assert Accounts.settings(c.target.id)["visits_suggestions_enabled"] == nil
    Application.put_env(:dawarich, Background, previous)
  end

  test "open background confirmation dialog has exactly one label per control", c do
    {:ok, view, _} = live(NativeAdminUI.conn(c.target), "/settings/background_jobs")
    render_hook(view, "open_job", %{"name" => "start_reverse_geocoding"})

    html =
      rendered_to_string(
        view.module.render(Map.put(:sys.get_state(view.pid).socket.assigns, :dialog_open, true))
      )

    assert Enum.count(
             LazyHTML.query(LazyHTML.from_fragment(html), "#background-job-confirm[open]")
           ) == 1

    assert NativeAdminUI.labels(html) == []
  end
end
