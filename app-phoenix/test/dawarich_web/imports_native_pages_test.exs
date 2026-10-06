defmodule DawarichWeb.ImportsNativePagesTest do
  use Dawarich.IngestCase, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Dawarich.Test.FormIsolation
  import Dawarich.Test.RailsFormRequests, only: [upstream!: 0, forwarded: 2]
  alias Dawarich.Test.{RailsUser, ImportsExportsSeeds}
  @endpoint DawarichWeb.Endpoint
  @reopen ~s(button[data-action="click->import-extraction#open"])
  setup do
    user = RailsUser.insert!(%{id: 7591, email: "native-pages@example.test"})
    ImportsExportsSeeds.import!(%{id: 759_101, user_id: user.id, name: "native.gpx"})

    Repo.query!(
      File.read!(
        Path.expand("../../priv/repo/sql/20261001170000_import_destroy_runs.sql", __DIR__)
      ),
      [],
      query_type: :text
    )

    Dawarich.Jobs.Ownership.put!(Repo, "command:imports.destroy", :oban)
    %{user: user}
  end

  defp live_as(user, path),
    do: live(RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id), path)

  test "new native page binds the upload controller to Rails' direct upload endpoint", c do
    {:ok, _view, html} = live_as(c.user, "/imports/new")

    assert html =~
             ~s(data-upload-url-value="http://www.example.com/rails/active_storage/direct_uploads")

    refute html =~ "/imports/direct_uploads"
    assert_form_isolated(html, "#phx-import-upload")
  end

  test "import rename and source selection share a stable patch isolation before and after join",
       c do
    path = "/imports/759101/edit"
    dead = RailsUser.signed_in(c.user.id) |> get(path) |> html_response(200)
    {:ok, view, joined} = live_as(c.user, path)

    for html <- [dead, joined, render(view)] do
      assert_form_isolated(html, "form[action='/imports/759101']")

      assert ["phx-import-edit-759101"] ==
               html
               |> LazyHTML.from_document()
               |> LazyHTML.query("form[phx-update='ignore']")
               |> LazyHTML.attribute("id")
    end
  end

  test "the owner's show and edit pages are native LiveViews", c do
    {:ok, _view, html} = live_as(c.user, "/imports/759101")
    assert html =~ "native.gpx"
    assert html =~ "data-phx-main"

    {:ok, _view, edit} = live_as(c.user, "/imports/759101/edit")
    assert edit =~ ~s(name="import[source]")
    assert edit =~ "data-phx-main"
  end

  test "a foreign import is shown by Rails while an owned non-GPX import is native", c do
    other = RailsUser.insert!(%{id: 7592, email: "foreign-pages@example.test"})
    ImportsExportsSeeds.import!(%{id: 759_102, user_id: c.user.id, name: "owned.kml", source: 9})
    upstream = upstream!()

    for {user_id, path} <- [
          {other.id, "/imports/759101"},
          {other.id, "/imports/759101/edit"}
        ] do
      {request, conn} = forwarded(upstream, fn -> get(RailsUser.signed_in(user_id), path) end)
      assert {request, conn.status} == {{"GET #{path} HTTP/1.1", ""}, 204}
    end

    for path <- ["/imports/759102", "/imports/759102/edit"] do
      {:ok, _view, html} = live_as(c.user, path)
      assert html =~ "owned.kml"
    end
  end

  test "connected index refreshes completed rows through owner-scoped native PubSub", c do
    {:ok, view, _} = live_as(c.user, "/imports")
    Repo.query!("UPDATE imports SET status=1,processed=4 WHERE id=759101")
    Dawarich.Imports.Events.broadcast(c.user.id)
    assert render(view) =~ "Processing"
    Repo.query!("UPDATE imports SET status=2,processed=11 WHERE id=759101")
    Dawarich.Imports.Events.broadcast(c.user.id)
    assert render(view) =~ "Completed"
    assert has_element?(view, "#import_759101 [data-points-count]", "11")
  end

  test "native row deletion uses an integer command payload and updates the live status", c do
    {:ok, view, _} = live_as(c.user, "/imports")

    view
    |> element("#import_759101 form[phx-submit=delete_import]")
    |> render_submit(%{"import_id" => "759101"})

    assert has_element?(view, "#import_759101 [data-status-display]", "Deleting")

    assert [[%{"import_id" => 759_101, "user_id" => 7591}]] =
             Repo.query!("SELECT payload FROM job_outbox WHERE command_type='imports.destroy'").rows
  end

  test "a non-GPX row keeps the Turbo delete link and supports owner-scoped native deletion", c do
    ImportsExportsSeeds.import!(%{id: 759_103, user_id: c.user.id, name: "owned.csv", source: 10})
    {:ok, view, _} = live_as(c.user, "/imports")
    refute has_element?(view, "#import_759103 form[phx-submit=delete_import]")

    assert has_element?(
             view,
             ~s(#import_759103 a[data-turbo-method=delete][href="/imports/759103"])
           )

    render_hook(view, "delete_import", %{"import_id" => "759103"})

    assert [[4]] = Repo.query!("SELECT status FROM imports WHERE id=759103").rows

    assert [[%{"import_id" => 759_103, "user_id" => 7591}]] =
             Repo.query!("SELECT payload FROM job_outbox").rows
  end

  test "a failed extraction card offers a retry and turns into start-over once it stalls", c do
    Repo.query!(
      "UPDATE imports SET raw_data=$1,additional_data_extraction_status=4,additional_data_extraction=$2 WHERE id=759101",
      [%{"waypoints_seen" => 1}, %{"error_message" => "real extraction failure"}]
    )

    {:ok, view, _} = live_as(c.user, "/imports/759101")
    assert render(view) =~ "real extraction failure"
    assert has_element?(view, @reopen, "Retry extraction")

    Repo.query!(
      "UPDATE imports SET additional_data_extraction_status=2,additional_data_extraction=$1 WHERE id=759101",
      [%{"started_at" => DateTime.to_iso8601(DateTime.add(DateTime.utc_now(), -21601))}]
    )

    Dawarich.Imports.Events.broadcast(c.user.id)
    assert has_element?(view, @reopen, "Start over")
  end

  test "the list polls while an import is unfinished and stops once every row is final", c do
    fast_polling()
    Repo.query!("UPDATE imports SET status=1 WHERE id=759101")
    {:ok, view, _} = live_as(c.user, "/imports")
    Repo.query!("UPDATE imports SET status=2,processed=11 WHERE id=759101")

    assert eventually(fn ->
             has_element?(view, "#import_759101 [data-status-display]", "Completed")
           end)

    refute_refresh(view)
  end

  test "a GPX import's page polls while its extraction runs and stops once it is final", c do
    Repo.query!(
      "UPDATE imports SET raw_data=$1,additional_data_extraction_status=2,additional_data_extraction=$2 WHERE id=759101",
      [%{"waypoints_seen" => 1}, %{"started_at" => DateTime.to_iso8601(DateTime.utc_now())}]
    )

    fast_polling()
    {:ok, view, _} = live_as(c.user, "/imports/759101")

    Repo.query!(
      "UPDATE imports SET additional_data_extraction_status=3,additional_data_extraction=$1 WHERE id=759101",
      [%{"counts" => %{"visits" => 2, "places" => 3, "tracks" => 4, "segments" => 5}}]
    )

    assert eventually(fn -> has_element?(view, @reopen, "Re-extract") end)
    refute_refresh(view)
  end

  test "a poll recounts the import's points only when the import itself changed", c do
    Repo.query!("UPDATE imports SET status=1 WHERE id=759101")
    {:ok, view, _} = live_as(c.user, "/imports/759101")
    assert has_element?(view, "[data-points-count]", "0")

    Repo.query!(
      "INSERT INTO points(user_id,import_id,timestamp,lonlat,created_at,updated_at) VALUES($1,759101,100,ST_SetSRID(ST_MakePoint(12.37,51.34),4326)::geography,now(),now())",
      [c.user.id]
    )

    send(view.pid, :imports_refresh)
    assert has_element?(view, "[data-points-count]", "0")

    Repo.query!("UPDATE imports SET processed=11 WHERE id=759101")
    send(view.pid, :imports_refresh)
    assert has_element?(view, "[data-points-count]", "1")
  end

  defp fast_polling do
    Application.put_env(:dawarich, :imports_poll_ms, 10)
    on_exit(fn -> Application.delete_env(:dawarich, :imports_poll_ms) end)
  end

  defp eventually(check, tries \\ 300) do
    cond do
      check.() ->
        true

      tries == 0 ->
        false

      true ->
        Process.sleep(10)
        eventually(check, tries - 1)
    end
  end

  defp refute_refresh(view) do
    :erlang.trace(view.pid, true, [:receive])
    pid = view.pid
    refute_receive {:trace, ^pid, :receive, :imports_refresh}, 200
  end
end
