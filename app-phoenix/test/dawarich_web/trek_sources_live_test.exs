defmodule DawarichWeb.TrekSourcesLiveTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Accounts.Scope
  alias Dawarich.Integrations.Trek
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.Translate
  @endpoint DawarichWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    rails = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      if rails,
        do: System.put_env("DAWARICH_RAILS", rails),
        else: System.delete_env("DAWARICH_RAILS")
    end)

    env = System.get_env("SELF_HOSTED")
    System.put_env("SELF_HOSTED", "true")

    on_exit(fn ->
      if env, do: System.put_env("SELF_HOSTED", env), else: System.delete_env("SELF_HOSTED")
    end)

    user =
      RailsUser.insert!(%{
        id: 8791,
        email: "native-trek-live@dawarich.test",
        settings: %{"timezone" => "UTC"}
      })

    %{user: user, url: Dawarich.Test.NativeIntegrationStub.start!()}
  end

  defp conn_for(user), do: RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id)
  defp page(user), do: live(conn_for(user), "/settings/integrations?service=trek")

  defp source(c) do
    {:ok, id} =
      Trek.create_source(Scope.for_user(Accounts.get(c.user.id), "en"), %{
        "base_url" => c.url,
        "api_key" => "synthetic-trek"
      })

    id
  end

  defp path(id), do: "/settings/trek_sources/#{id}/select_trips"
  defp rows(sql, args), do: Repo.query!(sql, args, log: false).rows

  defp escaped(key),
    do:
      Translate.t("en", "settings.trek_sources." <> key, %{})
      |> Phoenix.HTML.html_escape()
      |> Phoenix.HTML.safe_to_string()

  test "native create navigates to selection once with the Rails notice", c do
    {:ok, view, _} = page(c.user)

    view
    |> form("#trek-source-form")
    |> render_submit(%{"trip_source" => %{"base_url" => c.url, "api_key" => "synthetic-trek"}})

    [[id]] = rows("SELECT id FROM trip_sources WHERE user_id=$1", [c.user.id])
    {to, flash} = assert_redirect(view)
    assert to == path(id)

    assert flash["notice"] ==
             Translate.t("en", "settings.trek_sources.create.connected_choose_trips", %{})

    {:ok, selection, _} = live(conn_for(c.user), to)
    assert has_element?(selection, "#trek-trips")
    assert rows("SELECT count(*) FROM trip_sources WHERE user_id=$1", [c.user.id]) == [[1]]
    assert_receive {:native_provider_request, "/api/v1/trips"}
    assert_receive {:native_provider_request, "/api/v1/trips"}
    assert_receive {:native_provider_request, "/api/v1/trips"}
    scope = Scope.for_user(Accounts.get(c.user.id), "en")

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        current_scope: scope,
        locale: "en",
        flash: %{},
        trek_created: false
      }
    }

    params = %{"trip_source" => %{"base_url" => c.url, "api_key" => "synthetic-trek"}}

    {:noreply, saved} =
      DawarichWeb.SettingsLive.Integrations.handle_event("trek-create", params, socket)

    {:noreply, _} =
      DawarichWeb.SettingsLive.Integrations.handle_event("trek-create", params, %{
        saved
        | redirected: nil
      })

    assert_receive {:native_provider_request, "/api/v1/trips"}
    refute_receive {:native_provider_request, "/api/v1/trips"}
  end

  test "native sync queues once and confirmed disconnect retains managed trip data", c do
    id = source(c)
    Dawarich.Jobs.Ownership.put!(Repo, "command:imports.trek_sync", :oban)

    rows(
      "INSERT INTO trips(user_id,name,started_at,ended_at,trip_source_id,source_identifier,source_status,created_at,updated_at) VALUES($1,'Kept','2030-01-01','2030-01-02',$2,'dated',0,now(),now())",
      [c.user.id, id]
    )

    {:ok, view, _} = page(c.user)
    html = view |> element("#trek-sync-#{id}") |> render_click()
    assert html =~ escaped("sync.sync_queued")
    render_hook(view, "trek-sync", %{"id" => to_string(id)})
    assert rows("SELECT count(*) FROM job_outbox WHERE aggregate_id=$1", [id]) == [[1]]
    assert has_element?(view, "#trek-delete-#{id}[data-confirm][phx-disable-with]")
    html = view |> element("#trek-delete-#{id}") |> render_click()
    assert html =~ escaped("destroy.source_removed_trips_kept")
    assert rows("SELECT id FROM trip_sources WHERE id=$1", [id]) == []

    assert rows("SELECT name,trip_source_id FROM trips WHERE user_id=$1", [c.user.id]) == [
             ["Kept", nil]
           ]
  end

  test "native trip selection lists dated choices and importing publishes the chosen identifiers then returns",
       c do
    id = source(c)
    Dawarich.Jobs.Ownership.put!(Repo, "command:imports.trek_import", :oban)
    {:ok, view, _} = live(conn_for(c.user), path(id))
    assert has_element?(view, "input[value='dated']:not([disabled])")
    assert has_element?(view, "input[value='undated'][disabled]")
    assert has_element?(view, "input[value='archived'][disabled]")
    view |> form("#trek-trips") |> render_submit(%{"selection" => %{"trip_ids" => ["dated"]}})
    {to, flash} = assert_redirect(view)
    assert to == "/settings/integrations?service=trek"

    assert flash["notice"] ==
             Translate.t("en", "settings.trek_sources.import_trips.trips_are_now_syncing", %{})

    [[payload]] = rows("SELECT payload FROM job_outbox WHERE aggregate_id=$1", [id])
    assert payload["identifiers"] == ["dated"]
  end

  test "foreign malformed and HTML selection paths answer 404; provider errors disable the source",
       c do
    other = RailsUser.insert!(%{id: 8792, email: "native-trek-foreign@dawarich.test"})
    id = source(c)

    for {user, bad} <- [{other, id}, {c.user, "bad"}, {c.user, "#{id}.html"}] do
      assert_error_sent 404, fn -> get(conn_for(user), path(bad)) end
    end

    assert get(conn_for(c.user), path(id) <> ".html").status == 404
    rows("UPDATE trip_sources SET base_url=$2 WHERE id=$1", [id, c.url <> "/fail"])

    assert {:error, {:redirect, %{to: "/settings/integrations?service=trek", flash: flash}}} =
             live(conn_for(c.user), path(id))

    assert flash["alert"] == "TREK request failed with HTTP 401"

    assert rows("SELECT status,last_error FROM trip_sources WHERE id=$1", [id]) == [
             [1, "TREK request failed with HTTP 401"]
           ]
  end
end
