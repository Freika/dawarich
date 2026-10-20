defmodule DawarichWeb.ImportsNativePagesTest do
  use Dawarich.IngestCase, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias Dawarich.Test.{RailsUser, ImportsExportsSeeds}
  @endpoint DawarichWeb.Endpoint
  @reopen ~s(button[phx-click])
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

  test "new native page labels bounded multi-file uploads without a legacy endpoint", c do
    {:ok, view, html} = live_as(c.user, "/imports/new")
    assert has_element?(view, "label.form-control input#import_files")
    assert has_element?(view, "input#import_files[multiple][data-native-selection]")

    assert has_element?(
             view,
             "#phx-import-upload[data-upload-kind=imports][phx-submit=start_imports]"
           )

    assert has_element?(view, "#phx-import-upload input[type=submit][disabled]")
    refute html =~ "/rails/active_storage/direct_uploads"
    refute has_element?(view, "#phx-import-upload[phx-update=ignore], [data-controller=upload]")
  end

  test "native import rename and source selection remain labelled before and after join",
       c do
    path = "/imports/759101/edit"
    dead = RailsUser.signed_in(c.user.id) |> get(path) |> html_response(200)
    {:ok, view, joined} = live_as(c.user, path)

    for html <- [dead, joined, render(view)] do
      doc = LazyHTML.from_document(html)

      assert ["native.gpx"] ==
               doc |> LazyHTML.query("#import_name") |> LazyHTML.attribute("value")

      assert ["import_source"] ==
               doc |> LazyHTML.query("label[for=import_source]") |> LazyHTML.attribute("for")

      assert Enum.count(LazyHTML.query(doc, "form[phx-submit=save_import]")) == 1
      assert Enum.count(LazyHTML.query(doc, "form[phx-update=ignore]")) == 0
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

  test "foreign imports refuse to the safe index while owned non-GPX imports remain native", c do
    other = RailsUser.insert!(%{id: 7592, email: "foreign-pages@example.test"})
    ImportsExportsSeeds.import!(%{id: 759_102, user_id: c.user.id, name: "owned.kml", source: 9})

    for {user_id, path} <- [
          {other.id, "/imports/759101"},
          {other.id, "/imports/759101/edit"}
        ] do
      assert {:error, {:redirect, %{to: "/imports"}}} = live_as(%{id: user_id}, path)
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

  test "non-GPX row deletion uses the same owned native command", c do
    ImportsExportsSeeds.import!(%{id: 759_103, user_id: c.user.id, name: "owned.csv", source: 10})
    {:ok, view, _} = live_as(c.user, "/imports")
    assert has_element?(view, "#import_759103 form[phx-submit=delete_import]")
    refute has_element?(view, "[data-turbo-method]")

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

  test "native index progress wakes on invalidation and never installs an import poll", c do
    Repo.query!("UPDATE imports SET status=1 WHERE id=759101")
    {:ok, view, _} = live_as(c.user, "/imports")
    Repo.query!("UPDATE imports SET status=2,processed=11 WHERE id=759101")

    Dawarich.Imports.Events.broadcast(c.user.id)
    assert has_element?(view, "#import_759101 [data-status-display]", "Completed")

    refute_refresh(view)
  end

  test "native detail extraction completion wakes without an import poll", c do
    Repo.query!(
      "UPDATE imports SET raw_data=$1,additional_data_extraction_status=2,additional_data_extraction=$2 WHERE id=759101",
      [%{"waypoints_seen" => 1}, %{"started_at" => DateTime.to_iso8601(DateTime.utc_now())}]
    )

    {:ok, view, _} = live_as(c.user, "/imports/759101")

    Repo.query!(
      "UPDATE imports SET additional_data_extraction_status=3,additional_data_extraction=$1 WHERE id=759101",
      [%{"counts" => %{"visits" => 2, "places" => 3, "tracks" => 4, "segments" => 5}}]
    )

    Dawarich.Imports.Events.broadcast(c.user.id)
    assert has_element?(view, @reopen, "Re-extract")
    refute_refresh(view)
  end

  test "native invalidation recounts points only when the import itself changed", c do
    Repo.query!("UPDATE imports SET status=1 WHERE id=759101")
    {:ok, view, _} = live_as(c.user, "/imports/759101")
    assert has_element?(view, "[data-points-count]", "0")

    Repo.query!(
      "INSERT INTO points(user_id,import_id,timestamp,lonlat,created_at,updated_at) VALUES($1,759101,100,ST_SetSRID(ST_MakePoint(12.37,51.34),4326)::geography,now(),now())",
      [c.user.id]
    )

    send(view.pid, {:domain_changed, c.user.id, :imports})
    assert has_element?(view, "[data-points-count]", "0")

    Repo.query!("UPDATE imports SET processed=11 WHERE id=759101")
    send(view.pid, {:domain_changed, c.user.id, :imports})
    assert has_element?(view, "[data-points-count]", "1")
  end

  defp refute_refresh(view) do
    :erlang.trace(view.pid, true, [:receive])
    pid = view.pid
    refute_receive {:trace, ^pid, :receive, :imports_refresh}, 200
  end
end
