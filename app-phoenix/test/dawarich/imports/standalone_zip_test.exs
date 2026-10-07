defmodule Dawarich.Imports.StandaloneZipTest do
  use Dawarich.JobsCase
  import Phoenix.ConnTest
  import Plug.Conn
  alias Dawarich.{Repo, Jobs}
  alias Dawarich.Imports.Postprocessing.Commands
  alias Dawarich.Test.RailsUser

  setup do
    root = Path.join(System.tmp_dir!(), "standalone-zip-" <> Ecto.UUID.generate())
    File.mkdir_p!(root)
    previous_repo = Repo.put_dynamic_repo(ScratchRepo)
    previous = Application.fetch_env(:dawarich, :imports_storage)
    Application.put_env(:dawarich, :imports_storage, %{service: "local", root: root})

    on_exit(fn ->
      Repo.put_dynamic_repo(previous_repo)

      case previous do
        {:ok, storage} -> Application.put_env(:dawarich, :imports_storage, storage)
        :error -> Application.delete_env(:dawarich, :imports_storage)
      end

      File.rm_rf!(root)
    end)

    start_oban(__MODULE__)
    %{root: root}
  end

  test "standalone postprocessing uses the registered native owners for all import commands" do
    c = Dawarich.ImportLeaseFixture.create()
    rows("DELETE FROM oban.oban_jobs WHERE id=$1", [c.job.id])
    context = %{now: DateTime.utc_now(), zone: "Etc/UTC", locale: "en"}

    payload = %{
      "import_id" => c.import.id,
      "user_id" => c.import.user_id,
      "time_zone" => "Etc/UTC"
    }

    Dawarich.EnhancedImportCase.with_env("DAWARICH_RAILS", "off", fn ->
      for {type, args, worker} <- [
            {"imports.process_normal", payload, Dawarich.Imports.ProcessWorker},
            {"imports.process_gpx", payload, Dawarich.Imports.ProcessGpxWorker},
            {"imports.update_points_count", %{"import_id" => c.import.id},
             Dawarich.Imports.UpdatePointsCountWorker},
            {"tracks.generate_range", %{"user_id" => c.import.user_id},
             Dawarich.Tracks.RangeWorker}
          ] do
        Jobs.Ownership.put!(ScratchRepo, "command:" <> type, :sidekiq)
        assert :ok = Commands.produce!(ScratchRepo, c.import, context, type, args, c.import.id)
        assert :ok = Commands.produce!(ScratchRepo, c.import, context, type, args, c.import.id)

        assert [[stored]] =
                 rows("SELECT args FROM oban.oban_jobs WHERE worker=$1", [worker_name(worker)])

        assert Map.delete(stored, "event_id") == args
      end

      assert [] == rows("SELECT id FROM phoenix.rails_commands")
      assert [] == rows("SELECT event_id FROM job_outbox")
    end)
  end

  for mode <- ["on", "off"] do
    test "ZIP parent waits for all five terminal children in #{mode}",
         c do
      mode = unquote(mode)

      (fn ->
         reset!(ScratchRepo)

         user =
           RailsUser.insert!(
             %{
               id: 871_101,
               email: "zip@example.test",
               api_key: "synthetic-zip-map",
               settings: %{
                 "timezone" => "UTC",
                 "locale" => "en",
                 "visits_suggestions_enabled" => "false"
               }
             },
             ScratchRepo
           )

         session = RailsUser.session(user.id)

         for type <-
               ~w(imports.process_normal imports.process_gpx imports.update_points_count imports.prepared_download_purge),
             do: Jobs.Ownership.put!(ScratchRepo, "command:" <> type, :oban)

         Dawarich.EnhancedImportCase.with_env("DAWARICH_RAILS", mode, fn ->
           {:ok, {_, bytes}} = :zip.create(~c"mixed.zip", members(), [:memory])
           signed = direct_upload!(session, user, c.root, bytes)

           response =
             request(
               session,
               :post,
               "/imports",
               Plug.Conn.Query.encode(%{"import" => %{"files" => [signed]}}),
               "application/x-www-form-urlencoded"
             )

           assert response.status == 303
           assert [[parent]] = rows("SELECT id FROM imports WHERE user_id=$1", [user.id])
           assert %{dispatched: 1} = Jobs.Dispatch.run(repo: ScratchRepo, oban: __MODULE__)
           parent_job = job!(parent)
           assert {:snooze, 5} = Dawarich.Imports.ProcessWorker.perform(parent_job)
           assert [[1]] == rows("SELECT status FROM imports WHERE id=$1", [parent])

           assert [["built"]] ==
                    rows(
                      "SELECT phase FROM phoenix.import_archive_children WHERE parent_id=$1 AND entry_name=''",
                      [parent]
                    )

           refute Jobs.Processed.done?(ScratchRepo, parent_job.args["event_id"])

           children =
             rows(
               "SELECT child_id,entry_name,phase FROM phoenix.import_archive_children WHERE parent_id=$1 AND child_id IS NOT NULL ORDER BY entry_name",
               [parent]
             )

           assert length(children) == length(members())
           assert Enum.all?(children, fn [_, _, phase] -> phase == "queued" end)

           if mode == "on",
             do:
               assert(
                 Jobs.Dispatch.run(repo: ScratchRepo, oban: __MODULE__) == %{
                   dispatched: length(children)
                 }
               )

           for [child, _, _] <- children do
             job = job!(child)
             assert :ok = Dawarich.Imports.ProcessWorker.perform(job)

             assert [[2, nil]] ==
                      rows("SELECT status,error_message FROM imports WHERE id=$1", [child])

             assert Jobs.Processed.done?(ScratchRepo, job.args["event_id"])
             assert :ok = Dawarich.Imports.ProcessWorker.perform(job)

             if rows("SELECT source FROM imports WHERE id=$1", [child]) == [[4]] do
               rows("DELETE FROM phoenix.processed_commands WHERE event_id=$1", [
                 Ecto.UUID.dump!(job.args["event_id"])
               ])

               rows("UPDATE oban.oban_jobs SET attempt=2 WHERE id=$1", [job.id])
               assert :ok = Dawarich.Imports.ProcessWorker.perform(%{job | attempt: 2})

               assert [["imports.process_normal"]] ==
                        rows("SELECT handler FROM phoenix.processed_commands WHERE event_id=$1", [
                          Ecto.UUID.dump!(job.args["event_id"])
                        ])
             end
           end

           assert [] ==
                    rows(
                      "SELECT id FROM phoenix.rails_commands WHERE kind='imports.normal_resume'"
                    )

           assert [[5]] == rows("SELECT count(*) FROM points WHERE user_id=$1", [user.id])
           assert [[5]] == rows("SELECT points_count FROM users WHERE id=$1", [user.id])

           assert [["Import completed with no points", content, 1]] =
                    rows("SELECT title,content,kind FROM notifications WHERE user_id=$1", [
                      user.id
                    ])

           assert content =~ "empty.kml (from mixed.zip)"
           owner = self()
           [child | _] = hd(children)

           holder =
             Task.async(fn ->
               ScratchRepo.transaction(fn ->
                 rows("SELECT id FROM imports WHERE id=$1 FOR UPDATE", [child])
                 send(owner, :child_locked)

                 receive do
                   :release_child -> :ok
                 end
               end)
             end)

           assert_receive :child_locked

           try do
             assert {:snooze, 5} = Dawarich.Imports.ProcessWorker.perform(parent_job)
           after
             send(holder.pid, :release_child)
             assert {:ok, :ok} = Task.await(holder)
           end

           assert :ok = Dawarich.Imports.ProcessWorker.perform(parent_job)
           assert [] == rows("SELECT id FROM imports WHERE id=$1", [parent])
           assert Jobs.Processed.done?(ScratchRepo, parent_job.args["event_id"])

           assert [["removed"]] ==
                    rows(
                      "SELECT phase FROM phoenix.import_archive_children WHERE parent_id=$1 AND entry_name=''",
                      [parent]
                    )

           assert :ok = Dawarich.Imports.ProcessWorker.perform(parent_job)

           assert length(children) ==
                    length(rows("SELECT id FROM imports WHERE user_id=$1", [user.id]))

           assert File.ls!(c.root) != []

           conn =
             build_conn()
             |> put_req_header("authorization", "Bearer " <> user.api_key)
             |> dispatch(
               DawarichWeb.Endpoint,
               :get,
               "/api/v1/points?start_at=2026-01-15&end_at=2026-01-17"
             )

           assert conn.status == 200
           assert length(Jason.decode!(conn.resp_body)) == 5
         end)
       end).()
    end
  end

  defp members do
    [
      {~c"points.csv",
       "latitude,longitude,timestamp\n52.5,13.4,1768521600\n52.51,13.41,1768521660\n"},
      {~c"point.geojson",
       ~s({"type":"FeatureCollection","features":[{"type":"Feature","geometry":{"type":"Point","coordinates":[13.42,52.52]},"properties":{"timestamp":1768521720}}]})},
      {~c"route.gpx",
       ~s(<gpx><trk><trkseg><trkpt lat="52.53" lon="13.43"><time>2026-01-15T23:30:00Z</time></trkpt></trkseg></trk></gpx>)},
      {~c"track.tcx",
       File.read!(
         Path.expand("../../fixtures/imports/formats/tcx_import_singleton.input.json", __DIR__)
       )},
      {~c"empty.kml", "<kml><Document/></kml>"}
    ]
  end

  defp direct_upload!(session, user, root, bytes) do
    catalog = %{default: "local", services: %{"local" => %{service: "local", root: root}}}

    body = %{
      "blob" => %{
        "filename" => "mixed.zip",
        "byte_size" => byte_size(bytes),
        "checksum" => Base.encode64(:crypto.hash(:md5, bytes)),
        "content_type" => "application/zip"
      }
    }

    conn =
      Plug.Test.conn(:post, "http://www.example.com/rails/active_storage/direct_uploads", body)
      |> assign(:rails_session, session)
      |> assign(:current_user, user)
      |> put_req_header("x-csrf-token", DawarichWeb.RailsCsrf.masked_token(session))

    response = DawarichWeb.ActiveStorage.call(conn, action: :direct_upload, storage: catalog)
    assert response.status == 200
    blob = Jason.decode!(response.resp_body)
    url = blob["direct_upload"]["url"]

    token =
      url |> URI.parse() |> Map.fetch!(:path) |> String.split("/") |> List.last() |> URI.decode()

    conn =
      Plug.Test.conn(:put, url, bytes)
      |> put_req_header("content-type", "application/zip")
      |> put_req_header("content-length", Integer.to_string(byte_size(bytes)))

    response =
      DawarichWeb.ActiveStorage.call(%{conn | path_params: %{"encoded_token" => token}},
        action: :disk_update,
        storage: catalog
      )

    assert response.status == 204
    blob["signed_id"]
  end

  defp request(session, method, path, body, type) do
    build_conn()
    |> put_req_cookie("_dawarich_session", RailsUser.cookie(session))
    |> put_req_header("x-csrf-token", DawarichWeb.RailsCsrf.masked_token(session))
    |> put_req_header("content-type", type)
    |> put_req_header("content-length", Integer.to_string(byte_size(body)))
    |> dispatch(DawarichWeb.Endpoint, method, path, body)
  end

  defp job!(id) do
    [[job, args, worker]] =
      rows(
        "UPDATE oban.oban_jobs SET state='executing',attempt=1,attempted_at=now() WHERE args->>'import_id'=$1 AND worker='Dawarich.Imports.ProcessWorker' RETURNING id,args,worker",
        [to_string(id)]
      )

    %Oban.Job{id: job, args: args, worker: worker, attempt: 1}
  end

  defp worker_name(worker), do: worker |> Atom.to_string() |> String.trim_leading("Elixir.")
end
