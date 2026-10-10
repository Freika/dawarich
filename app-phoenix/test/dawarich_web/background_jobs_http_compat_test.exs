defmodule DawarichWeb.BackgroundJobsHttpCompatTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Test.{RailsFormRequests, RailsUser}
  alias DawarichWeb.RailsCsrf

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    prior = Map.new(~w(SELF_HOSTED DAWARICH_RAILS FORCE_SSL), &{&1, System.get_env(&1)})
    System.put_env(%{"SELF_HOSTED" => "true", "DAWARICH_RAILS" => "off", "FORCE_SSL" => "false"})
    for spec <- Dawarich.Redis.cache_child_specs(), do: start_supervised!(spec)

    on_exit(fn ->
      for {key, value} <- prior do
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end
    end)

    RailsUser.insert!(%{
      id: 10731,
      email: "background-http@example.invalid",
      settings: %{"timezone" => "Europe/Berlin"}
    })

    for kind <-
          ~w(imports.immich_geodata imports.photoprism_geodata imports.airtrail_flights imports.teslamate_sync geocoding.reverse_point),
        do: Dawarich.Jobs.Ownership.put!(Repo, "command:" <> kind, :oban)

    %{session: RailsUser.session(10731)}
  end

  test "shared import POST remains available with original session csrf query and Cloud rules",
       c do
    jobs = [
      {"start_immich_import", "/imports"},
      {"start_photoprism_import", "/imports"},
      {"start_airtrail_import", "/settings/integrations"},
      {"start_teslamate_sync", "/settings/integrations?service=teslamate"},
      {"start_reverse_geocoding", "/settings/background_jobs"},
      {"continue_reverse_geocoding", "/settings/background_jobs"}
    ]

    for {job, path} <- jobs do
      conn = post(c.session, job)
      assert conn.status == 302
      assert get_resp_header(conn, "location") == ["http://www.example.com" <> path]
    end

    assert count("job_outbox") == 4 and count("oban.oban_jobs") == 2

    assert Repo.query!("SELECT DISTINCT metadata FROM job_outbox", [], log: false).rows == [
             [%{"producer" => "Phoenix integration trigger"}]
           ]

    assert post(c.session, "unknown").status == 422

    assert post(c.session, "start_immich_import", %{"authenticity_token" => "invalid"}).status ==
             422

    assert post(c.session, "start_immich_import", %{}, [{"origin", "http://foreign.invalid"}]).status ==
             422

    assert post(%{}, "start_immich_import").status == 302

    for value <- ["false", "true"] do
      query = URI.encode_query(%{"settings[visits_suggestions_enabled]" => value})

      body =
        URI.encode_query(%{
          "_method" => "patch",
          "authenticity_token" => RailsCsrf.masked_token(c.session)
        })

      conn =
        RailsFormRequests.post_form(c.session, body, [], "/settings/background_jobs?" <> query)

      assert conn.status == 302
      assert Accounts.settings(10731)["visits_suggestions_enabled"] == value
    end

    assert count("job_outbox") == 4 and count("oban.oban_jobs") == 2
    System.put_env("SELF_HOSTED", "false")

    for {job, path} <- Enum.take(jobs, 4) do
      conn = post(c.session, job)
      assert conn.status == 302
      assert get_resp_header(conn, "location") == ["http://www.example.com" <> path]
    end

    for {job, _} <- Enum.drop(jobs, 4), do: assert(post(c.session, job).status == 303)
    assert count("job_outbox") == 8 and count("oban.oban_jobs") == 2
  end

  defp post(session, job, values \\ %{}, headers \\ []) do
    params = Map.merge(%{"authenticity_token" => RailsCsrf.masked_token(session)}, values)

    if job == "start_airtrail_import" do
      RailsFormRequests.post_form(
        session,
        URI.encode_query(Map.put(params, "job_name", job)),
        headers,
        "/settings/background_jobs"
      )
    else
      RailsFormRequests.post_form(
        session,
        URI.encode_query(params),
        headers,
        "/settings/background_jobs?" <> URI.encode_query(%{"job_name" => job})
      )
    end
  end

  defp count(table),
    do: Repo.query!("SELECT count(*) FROM #{table}", [], log: false).rows |> hd() |> hd()
end
