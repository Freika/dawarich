defmodule DawarichWeb.ImportsNativeEventsTest do
  use Dawarich.IngestCase, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias Dawarich.Test.{RailsUser, ImportsExportsSeeds}
  @endpoint DawarichWeb.Endpoint

  setup do
    user = RailsUser.insert!(%{id: 10951, email: "import-events@example.invalid"})

    ImportsExportsSeeds.import!(%{
      id: 109_510,
      user_id: user.id,
      name: "native-events.gpx",
      raw_data: %{"waypoints_seen" => 1}
    })

    for command <- ~w(imports.destroy enhanced_import.extract_gpx enhanced_import.destroy_gpx),
        do: Dawarich.Jobs.Ownership.put!(Repo, "command:" <> command, :oban)

    %{user: user}
  end

  defp live_as(user, path),
    do: live(RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id), path)

  test "committed import progress survives missed delivery reconnect and duplicate wakeups", c do
    {:ok, view, _} = live_as(c.user, "/imports")
    Repo.query!("UPDATE imports SET status=1,processed=4 WHERE id=109510", [], log: false)
    Dawarich.Imports.Events.broadcast(c.user.id)
    assert has_element?(view, "#import_109510 [data-points-count]", "4")
    Repo.query!("UPDATE imports SET status=2,processed=11 WHERE id=109510", [], log: false)
    {:ok, reconnected, _} = live_as(c.user, "/imports")
    assert has_element?(reconnected, "#import_109510 [data-points-count]", "11")
    telemetry = {__MODULE__, self()}

    :ok =
      :telemetry.attach(
        telemetry,
        [:dawarich, :repo, :query],
        fn _, _, meta, pid ->
          if String.contains?(meta.query || "", "FROM public.imports i") and
               String.contains?(meta.query || "", "count(*) OVER"),
             do: send(pid, :import_snapshot)
        end,
        self()
      )

    on_exit(fn -> :telemetry.detach(telemetry) end)
    :sys.suspend(reconnected.pid)
    for _ <- 1..2, do: send(reconnected.pid, {:domain_changed, c.user.id, :imports})
    :sys.resume(reconnected.pid)
    assert has_element?(reconnected, "#import_109510 [data-status-display]", "Completed")
    assert_receive :import_snapshot
    refute_receive :import_snapshot, 20
    refute Map.get(:sys.get_state(reconnected.pid).socket.assigns, :polling, false)
  end

  test "a revoked owner receives no queued update and cannot rename or delete", c do
    {:ok, view, _} = live_as(c.user, "/imports/109510")
    socket = :sys.get_state(view.pid).socket

    Repo.query!(
      "UPDATE users SET encrypted_password='revoked-import-session' WHERE id=$1",
      [c.user.id],
      log: false
    )

    assert {:halt, cleared} = DawarichWeb.NativeJobsAuth.authorize(socket)
    assert cleared.assigns.record == nil
    send(view.pid, {:domain_changed, c.user.id, :imports})
    assert_redirect(view, "/users/sign_in")

    assert {:error, :stale_session} =
             Dawarich.Imports.update(socket.assigns.current_scope, 109_510, %{"name" => "forged"})

    assert {:error, :stale_session} =
             Dawarich.Imports.delete(socket.assigns.current_scope, 109_510)

    assert [["native-events.gpx", 2]] =
             Repo.query!("SELECT name,status FROM imports WHERE id=109510", [], log: false).rows
  end

  test "failed extraction retries once and removal clears progress without a Turbo request", c do
    Repo.query!(
      "UPDATE imports SET additional_data_extraction_status=4,additional_data_extraction=$1 WHERE id=109510",
      [%{"error_message" => "synthetic extraction failure"}],
      log: false
    )

    {:ok, view, _} = live_as(c.user, "/imports/109510")
    assert has_element?(view, "button[phx-click]", "Retry extraction")
    render_hook(view, "extract_import", %{"trust_source" => "false"})
    render_hook(view, "extract_import", %{"trust_source" => "false"})

    assert [[1]] =
             Repo.query!(
               "SELECT count(*) FROM oban.oban_jobs WHERE worker='Dawarich.EnhancedImport.NormalWorker'",
               [],
               log: false
             ).rows

    assert [[%{"trust_source" => false}]] =
             Repo.query!(
               "SELECT additional_data_extraction->'options' FROM imports WHERE id=109510",
               [],
               log: false
             ).rows

    Repo.query!(
      "UPDATE imports SET additional_data_extraction_status=3,additional_data_extraction=$1 WHERE id=109510",
      [%{"counts" => %{"tracks" => 2}}],
      log: false
    )

    send(view.pid, {:domain_changed, c.user.id, :imports})
    assert has_element?(view, "button[phx-click=remove_extraction]", "Remove extracted data")
    render_hook(view, "remove_extraction", %{})

    assert [[2]] =
             Repo.query!(
               "SELECT additional_data_extraction_status FROM imports WHERE id=109510",
               [],
               log: false
             ).rows

    Repo.query!(
      "UPDATE imports SET additional_data_extraction_status=0,additional_data_extraction='{}' WHERE id=109510",
      [],
      log: false
    )

    send(view.pid, {:domain_changed, c.user.id, :imports})
    assert has_element?(view, "button[phx-click]", "Extract additional data")
    refute has_element?(view, "turbo-frame, [data-controller], [data-turbo-method]")
  end

  test "a forged source renders validation in place without changing the import", c do
    {:ok, view, _} = live_as(c.user, "/imports/109510/edit")
    render_hook(view, "save_import", %{"import" => %{"source" => "forged", "name" => "changed"}})

    assert [["native-events.gpx", 4]] =
             Repo.query!("SELECT name,source FROM imports WHERE id=109510", [], log: false).rows

    assert has_element?(view, "[role=alert]")
    assert has_element?(view, "#import_name[value='native-events.gpx']")
  end

  test "native rename retains Rails notices for rejected names without changing records", c do
    ImportsExportsSeeds.import!(%{id: 109_511, user_id: c.user.id, name: "duplicate.gpx"})

    for name <- ["", "duplicate.gpx"] do
      {:ok, view, _} = live_as(c.user, "/imports/109510/edit")
      render_hook(view, "save_import", %{"import" => %{"name" => name, "source" => "gpx"}})
      assert assert_redirect(view, "/imports")["notice"] == "Import was successfully updated."

      assert [["native-events.gpx", 4]] =
               Repo.query!("SELECT name,source FROM imports WHERE id=109510", [], log: false).rows
    end

    assert [] =
             Repo.query!(
               "SELECT id FROM oban.oban_jobs WHERE worker='Dawarich.Imports.EventsWorker'",
               [],
               log: false
             ).rows

    {:ok, view, _} = live_as(c.user, "/imports/109510/edit")
    render_hook(view, "save_import", %{"import" => %{"name" => "renamed.csv", "source" => "csv"}})
    assert assert_redirect(view, "/imports")["notice"] == "Import was successfully updated."

    assert [["renamed.csv", 10, 5]] =
             Repo.query!(
               "SELECT name,source,additional_data_extraction_status FROM imports WHERE id=109510",
               [],
               log: false
             ).rows

    assert [[1]] =
             Repo.query!(
               "SELECT count(*) FROM oban.oban_jobs WHERE worker='Dawarich.Imports.EventsWorker'",
               [],
               log: false
             ).rows
  end

  test "deleted import clears an open editor before any later update", c do
    {:ok, view, _} = live_as(c.user, "/imports/109510/edit")
    socket = :sys.get_state(view.pid).socket
    Repo.query!("DELETE FROM imports WHERE id=109510", [], log: false)
    Dawarich.Imports.Events.broadcast(c.user.id)
    assert_redirect(view, "/imports")

    assert {:noreply, cleared} =
             DawarichWeb.ImportsLive.Edit.handle_params(%{"id" => "109510"}, "", socket)

    assert cleared.assigns.record == nil

    assert [] =
             Repo.query!(
               "SELECT id FROM oban.oban_jobs WHERE worker='Dawarich.Imports.EventsWorker'",
               [],
               log: false
             ).rows
  end
end
