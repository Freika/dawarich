defmodule DawarichWeb.BackgroundJobsHttpCompatTest do
  use ExUnit.Case, async: false
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Test.{RailsFormRequests, RailsUser}
  alias DawarichWeb.RailsCsrf
  alias Dawarich.Accounts.Scope
  alias Dawarich.Admin.Background

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
      settings: %{
        "timezone" => "Europe/Berlin",
        "immich_url" => "http://immich.invalid",
        "immich_api_key" => "synthetic",
        "photoprism_url" => "http://photoprism.invalid",
        "photoprism_api_key" => "synthetic"
      }
    })

    for kind <-
          ~w(imports.immich_geodata imports.photoprism_geodata imports.airtrail_flights imports.teslamate_sync geocoding.reverse_point),
        do: Dawarich.Jobs.Ownership.put!(Repo, "command:" <> kind, :oban)

    %{session: RailsUser.session(10731), scope: Scope.for_user(Accounts.get(10731), "en")}
  end

  test "retired shared POST preserves all query and CSRF vectors while scoped commands preserve Cloud rules",
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
      assert conn.status == 404
      assert_job(c.scope, job, path)
    end

    assert count("job_outbox") == 4 and count("oban.oban_jobs") == 2

    assert Repo.query!("SELECT DISTINCT metadata FROM job_outbox", [], log: false).rows == [
             [%{"producer" => "Phoenix integration trigger"}]
           ]

    assert post(c.session, "unknown").status == 404

    assert post(c.session, "start_immich_import", %{"authenticity_token" => "invalid"}).status ==
             404

    assert post(c.session, "start_immich_import", %{}, [{"origin", "http://foreign.invalid"}]).status ==
             404

    assert post(%{}, "start_immich_import").status == 404

    for value <- ["false", "true"] do
      query = URI.encode_query(%{"settings[visits_suggestions_enabled]" => value})

      body =
        URI.encode_query(%{
          "_method" => "patch",
          "authenticity_token" => RailsCsrf.masked_token(c.session)
        })

      conn =
        RailsFormRequests.post_form(c.session, body, [], "/settings/background_jobs?" <> query)

      assert conn.status == 404
      refute Accounts.settings(10731)["visits_suggestions_enabled"] == value

      assert {:ok, _} =
               Background.update_visits(c.scope, %{"visits_suggestions_enabled" => value})

      assert Accounts.settings(10731)["visits_suggestions_enabled"] == value
    end

    assert count("job_outbox") == 4 and count("oban.oban_jobs") == 2
    System.put_env("SELF_HOSTED", "false")

    for {job, path} <- Enum.take(jobs, 4) do
      conn = post(c.session, job)
      assert conn.status == 404
      assert_job(c.scope, job, path)
    end

    for {job, _} <- Enum.drop(jobs, 4) do
      assert post(c.session, job).status == 404
      assert {:error, :cloud} = Background.request_job(c.scope, job)
    end

    assert count("job_outbox") == 8 and count("oban.oban_jobs") == 2
  end

  defp assert_job(scope, name, path) do
    result =
      case name do
        "start_immich_import" -> Dawarich.Imports.request_provider(scope, name)
        "start_photoprism_import" -> Dawarich.Imports.request_provider(scope, name)
        "start_airtrail_import" -> Dawarich.Integrations.start_sync(scope, :airtrail)
        "start_teslamate_sync" -> Dawarich.Integrations.start_sync(scope, :teslamate)
        _ -> Background.request_job(scope, name)
      end

    if name in ~w(start_reverse_geocoding continue_reverse_geocoding) do
      assert {:ok, %{destination: ^path}} = result
    else
      assert {:ok, :queued} = result
    end
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
