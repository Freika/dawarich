defmodule DawarichWeb.TripExportTest do
  use Dawarich.IngestCase, async: false
  import Plug.Conn
  import Dawarich.Test.RailsFormRequests
  alias Dawarich.{PointExports, Repo}
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Test.{RailsUser, TripsSeeds}
  alias Dawarich.Trips.WebExport

  @effects File.read!("test/fixtures/trips/remaining/effects.json")
           |> Jason.decode!()
           |> Map.fetch!("effects")
  @responses File.read!("test/fixtures/trips/remaining/responses.json")
             |> Jason.decode!()
             |> Map.fetch!("responses")

  defmodule FailedExport do
    defdelegate transaction(fun), to: Dawarich.Repo
    defdelegate query(sql, params), to: Dawarich.Repo

    def query!(sql, params, opts \\ []) do
      if String.contains?(sql, "INSERT INTO exports"), do: raise("synthetic export SQL failure")
      Dawarich.Repo.query!(sql, params, opts)
    end
  end

  defp naive(raw), do: raw |> DateTime.from_iso8601() |> elem(1) |> DateTime.to_naive()

  defp counts,
    do:
      Repo.query!(
        "SELECT (SELECT count(*) FROM exports),(SELECT count(*) FROM job_outbox),(SELECT count(*) FROM phoenix.rails_commands)"
      ).rows

  test "trip export preserves local name date range and owner" do
    previous = Application.get_env(:dawarich, :jobs_repo)
    Application.put_env(:dawarich, :jobs_repo, Repo)
    on_exit(fn -> Application.put_env(:dawarich, :jobs_repo, previous) end)

    for entry <- @effects, String.starts_with?(entry["name"], "export_") do
      actor = entry["before"]["actor"]

      RailsUser.insert!(%{
        id: actor["id"],
        email: "a8-export-#{actor["id"]}@example.invalid",
        settings: actor["settings"]
      })

      user = Dawarich.Accounts.get(actor["id"])
      [trip] = entry["before"]["trips"]

      TripsSeeds.trip!(%{
        id: trip["id"],
        user_id: user.id,
        name: trip["name"],
        started_at: naive(trip["started_at"]),
        ended_at: naive(trip["ended_at"])
      })

      Ownership.put!(
        Repo,
        "command:exports.points",
        String.to_existing_atom(entry["request"]["owner"])
      )

      format =
        entry["request"]["path"]
        |> URI.parse()
        |> Map.fetch!(:query)
        |> URI.decode_query()
        |> Map.fetch!("file_format")

      before = counts()
      result = WebExport.prepare(Repo, user, trip["id"], format, %{})
      session = RailsUser.session(user.id)

      raw =
        Plug.Conn.Query.encode(%{
          "authenticity_token" => DawarichWeb.RailsCsrf.masked_token(session)
        })

      path = "/trips/#{trip["id"]}/export?" <> URI.encode_query(%{"file_format" => format})

      cond do
        format not in ~w(gpx json) ->
          assert {:invalid, :format} = result
          conn = post_form(session, raw, [], path)
          expected = Enum.find(@responses, &(&1["name"] == entry["name"]))
          assert conn.status == 422
          assert get_resp_header(conn, "location") == [expected["location"]]
          assert rails_session(conn)["flash"]["flashes"] == expected["flash"]
          assert counts() == before

        true ->
          assert {:ok, export} = result
          [expected] = entry["after"]["exports"]
          assert export.name == expected["name"]

          assert {export.start_at, export.end_at} ==
                   {naive(trip["started_at"]), naive(trip["ended_at"])}

          conn = post_form(session, raw, [], path)
          assert conn.status == 302
          assert get_resp_header(conn, "location") == ["http://www.example.com/exports"]
          expected_response = Enum.find(@responses, &(&1["name"] == entry["name"]))
          assert rails_session(conn)["flash"]["flashes"] == expected_response["flash"]

          [[id, name, status, file_format, file_type, started, ended]] =
            Repo.query!(
              "SELECT id,name,status,file_format,file_type,start_at,end_at FROM exports WHERE user_id = $1",
              [user.id]
            ).rows

          assert {name, status, file_type, started, ended} ==
                   {export.name, 0, 0, export.start_at, export.end_at}

          assert file_format == if(format == "json", do: 0, else: 1)

          if entry["request"]["owner"] == "oban" do
            assert Repo.query!(
                     "SELECT payload FROM job_outbox WHERE aggregate_id = $1 AND command_type = 'exports.points'",
                     [id]
                   ).rows == [
                     [%{"export_id" => id, "user_id" => user.id, "time_zone" => "Europe/Berlin"}]
                   ]
          else
            assert Repo.query!(
                     "SELECT payload FROM phoenix.rails_commands WHERE kind = 'exports.points_created' AND payload->>'export_id' = $1",
                     [Integer.to_string(id)]
                   ).rows == [[%{"export_id" => id, "user_id" => user.id, "locale" => "en"}]]
          end

          before = counts()
          assert {:error, _} = PointExports.create(export, user, "en", FailedExport)
          assert counts() == before
          Application.put_env(:dawarich, :jobs_repo, FailedExport)
          failed = post_form(session, raw, [], path)
          Application.put_env(:dawarich, :jobs_repo, Repo)
          assert failed.status == 422

          assert get_resp_header(failed, "location") == [
                   "http://www.example.com/trips/#{trip["id"]}"
                 ]

          assert rails_session(failed)["flash"]["flashes"]["alert"] ==
                   "Export failed to initiate. Please try again."

          assert counts() == before
      end

      assert {:error, :not_found} =
               WebExport.prepare(Repo, %{user | id: user.id + 1_000_000}, trip["id"], format, %{})
    end
  end
end
