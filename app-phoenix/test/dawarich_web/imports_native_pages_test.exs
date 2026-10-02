defmodule DawarichWeb.ImportsNativePagesTest do
  use Dawarich.IngestCase, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Dawarich.Test.RailsFormRequests, only: [upstream!: 0, forwarded: 2]
  alias Dawarich.Test.{RailsUser, ImportsExportsSeeds}
  @endpoint DawarichWeb.Endpoint
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
    assert html =~ "native-imports-root"
    assert html =~ "import-file-input"

    assert html =~
             ~s(data-upload-url-value="http://www.example.com/rails/active_storage/direct_uploads")

    refute html =~ "/imports/direct_uploads"
  end

  test "owner show and edit pages are native LiveViews", c do
    {:ok, _view, html} = live_as(c.user, "/imports/759101")
    assert html =~ "native.gpx"
    assert html =~ "native-imports-root"
    {:ok, _view, html} = live_as(c.user, "/imports/759101/edit")
    assert html =~ "import[name]"
    assert html =~ "import[source]"
  end

  test "a foreign import and an owned non-GPX import are shown by Rails", c do
    other = RailsUser.insert!(%{id: 7592, email: "foreign-pages@example.test"})
    ImportsExportsSeeds.import!(%{id: 759_102, user_id: c.user.id, name: "owned.kml", source: 9})
    upstream = upstream!()

    for {user_id, path} <- [
          {other.id, "/imports/759101"},
          {other.id, "/imports/759101/edit"},
          {c.user.id, "/imports/759102"},
          {c.user.id, "/imports/759102/edit"}
        ] do
      {request, conn} = forwarded(upstream, fn -> get(RailsUser.signed_in(user_id), path) end)
      assert {request, conn.status} == {{"GET #{path} HTTP/1.1", ""}, 204}
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

  test "a non-GPX row keeps Rails' delete link and its delete event never runs natively", c do
    ImportsExportsSeeds.import!(%{id: 759_103, user_id: c.user.id, name: "owned.csv", source: 10})
    {:ok, view, _} = live_as(c.user, "/imports")
    refute has_element?(view, "#import_759103 form[phx-submit=delete_import]")

    assert has_element?(
             view,
             ~s(#import_759103 a[data-turbo-method=delete][href="/imports/759103"])
           )

    render_hook(view, "delete_import", %{"import_id" => "759103"})

    assert [[2]] = Repo.query!("SELECT status FROM imports WHERE id=759103").rows
    assert [] = Repo.query!("SELECT event_id FROM job_outbox").rows
  end

  test "native extraction card renders counts, trust choice and removal controls", c do
    Repo.query!(
      "UPDATE imports SET raw_data=$1,additional_data_extraction_status=3,additional_data_extraction=$2 WHERE id=759101",
      [
        %{"waypoints_seen" => 1},
        %{"counts" => %{"visits" => 2, "places" => 3, "tracks" => 4, "segments" => 5}}
      ]
    )

    {:ok, view, _} = live_as(c.user, "/imports/759101")
    assert has_element?(view, "[data-extraction-count=visits]", "2")
    assert has_element?(view, "[data-extraction-count=places]", "3")
    assert has_element?(view, "[data-extraction-count=tracks]", "4")
    assert has_element?(view, "[data-extraction-count=segments]", "5")
    assert has_element?(view, "input[name=trust_source][value=false]")
    assert has_element?(view, "[data-testid=import-extraction-remove]")
    assert has_element?(view, "[data-testid=import-extraction-submit]", "Re-extract")
  end

  test "failed and stalled native extraction cards permit recovery", c do
    Repo.query!(
      "UPDATE imports SET raw_data=$1,additional_data_extraction_status=4,additional_data_extraction=$2 WHERE id=759101",
      [%{"waypoints_seen" => 1}, %{"error_message" => "real extraction failure"}]
    )

    {:ok, view, _} = live_as(c.user, "/imports/759101")
    assert render(view) =~ "real extraction failure"
    assert has_element?(view, "[data-testid=import-extraction-submit]", "Retry extraction")

    Repo.query!(
      "UPDATE imports SET additional_data_extraction_status=2,additional_data_extraction=$1 WHERE id=759101",
      [%{"started_at" => DateTime.to_iso8601(DateTime.add(DateTime.utc_now(), -21601))}]
    )

    Dawarich.Imports.Events.broadcast(c.user.id)
    assert has_element?(view, "[data-testid=import-extraction-submit]", "Start over")
  end
end
