defmodule Dawarich.Admin.BackgroundTest do
  use ExUnit.Case, async: false
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Accounts.Scope
  alias Dawarich.Admin.{Background, OperatorGrant}
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Test.RailsUser

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    start_supervised!(
      {Oban,
       name: BackgroundDomainOban,
       repo: Repo,
       prefix: "oban",
       testing: :manual,
       notifier: Oban.Notifiers.PG}
    )

    start_supervised!(hd(Dawarich.Redis.cache_child_specs()))

    prior =
      Map.new(
        ~w(SELF_HOSTED DAWARICH_RAILS SIDEKIQ_USERNAME SIDEKIQ_PASSWORD),
        &{&1, System.get_env(&1)}
      )

    System.put_env(%{"SELF_HOSTED" => "true", "DAWARICH_RAILS" => "off"})
    previous_config = Application.get_env(:dawarich, Background)
    Application.put_env(:dawarich, Background, %{oban: BackgroundDomainOban})

    on_exit(fn ->
      for {key, value} <- prior do
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end

      if previous_config,
        do: Application.put_env(:dawarich, Background, previous_config),
        else: Application.delete_env(:dawarich, Background)
    end)

    RailsUser.insert!(%{
      id: 10721,
      email: "background-user@example.invalid",
      admin: true,
      settings: %{
        "timezone" => "Europe/Berlin",
        "locale" => "de",
        "immich_url" => "https://immich.example.invalid",
        "anomaly_rules_recalculation_queued_at" => "2026-10-10"
      }
    })

    for kind <-
          ~w(imports.immich_geodata imports.photoprism_geodata imports.airtrail_flights imports.teslamate_sync geocoding.reverse_point),
        do: Ownership.put!(Repo, "command:" <> kind, :oban)

    %{scope: Scope.for_user(Accounts.get(10721), "de")}
  end

  test "background page keeps ordinary access and only current admins receive health", %{
    scope: scope
  } do
    assert {:ok, %{visits: true, notice: true, health: health}} = Background.page(scope)
    assert is_map(health)
    Repo.query!("UPDATE users SET admin=false WHERE id=10721", [], log: false)
    owner = self()
    handler = "background-health-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler,
      [:dawarich, :repo, :query],
      fn _, _, meta, _ -> send(owner, {:query, meta.query}) end,
      nil
    )

    try do
      assert {:ok, %{health: nil}} = Background.page(scope)
      refute_receive {:query, "SELECT key, owner" <> _}
      refute_receive {:query, "SELECT worker, state" <> _}
    after
      :telemetry.detach(handler)
    end
  end

  test "ordinary visits update stores source strings without dispatch", %{scope: scope} do
    Repo.query!("UPDATE users SET admin=false WHERE id=10721", [], log: false)

    for value <- ["false", "true"] do
      assert {:ok, 10721} =
               Background.update_visits(scope, %{
                 "visits_suggestions_enabled" => value,
                 "immich_url" => "https://evil.invalid"
               })

      assert Accounts.settings(10721)["visits_suggestions_enabled"] == value
      assert Accounts.settings(10721)["immich_url"] == "https://immich.example.invalid"
      assert {:ok, page} = Background.page(scope)
      assert page.visits == (value == "true")
      assert count("job_outbox") == 0 and count("oban.oban_jobs") == 0
    end
  end

  test "six allowed jobs retain command owner payload and destination", %{scope: scope} do
    Repo.query!("UPDATE users SET admin=false,plan=0,status=0 WHERE id=10721", [], log: false)

    for {job, path} <- [
          {"start_immich_import", "/imports"},
          {"start_photoprism_import", "/imports"},
          {"start_airtrail_import", "/settings/integrations"},
          {"start_teslamate_sync", "/settings/integrations?service=teslamate"},
          {"start_reverse_geocoding", "/settings/background_jobs"},
          {"continue_reverse_geocoding", "/settings/background_jobs"}
        ] do
      assert {:ok,
              %{
                destination: ^path,
                notice_key: "controllers.settings.background_jobs.job_was_successfully_created"
              }} = Background.request_job(scope, job)
    end

    assert Repo.query!(
             "SELECT command_type,payload,metadata FROM job_outbox ORDER BY command_type",
             [],
             log: false
           ).rows ==
             Enum.map(
               ~w(imports.airtrail_flights imports.immich_geodata imports.photoprism_geodata imports.teslamate_sync),
               fn kind ->
                 payload =
                   if kind in ~w(imports.immich_geodata imports.photoprism_geodata),
                     do: %{"user_id" => 10721, "time_zone" => "Europe/Berlin"},
                     else: %{"user_id" => 10721}

                 [kind, payload, %{"producer" => "Phoenix integration trigger"}]
               end
             )

    assert Repo.query!("SELECT args FROM oban.oban_jobs ORDER BY id", [], log: false).rows ==
             Enum.map(
               [true, false],
               &[%{"user_id" => 10721, "force" => &1, "after_id" => 0, "locale" => "de"}]
             )

    assert Background.request_job(scope, "unknown") == {:error, :unknown_job}
    assert Background.request_job(scope, %{}) == {:error, :unknown_job}
    Ownership.put!(Repo, "command:imports.teslamate_sync", :sidekiq)
    assert Background.request_job(scope, "start_teslamate_sync") == {:error, :not_owned}
    Repo.query!("CREATE TEMP TABLE background_failures (n integer)", [], log: false)

    Repo.query!(
      "CREATE FUNCTION pg_temp.reject_background_intent() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN INSERT INTO background_failures VALUES(1); RAISE EXCEPTION 'synthetic enqueue failure'; END $$",
      [],
      log: false
    )

    Repo.query!(
      "CREATE TRIGGER reject_background_intent BEFORE INSERT ON job_outbox FOR EACH ROW EXECUTE FUNCTION pg_temp.reject_background_intent()",
      [],
      log: false
    )

    assert Background.request_job(scope, "start_airtrail_import") == {:error, :enqueue_failed}
    assert count("background_failures") == 0 and count("job_outbox") == 4
  end

  test "background admission refuses stale identities OIDC toggles and unproved Cloud operators",
       %{scope: scope} do
    oidc = %{
      "SELF_HOSTED" => "true",
      "OIDC_CLIENT_ID" => "synthetic",
      "OIDC_CLIENT_SECRET" => "synthetic"
    }

    Application.put_env(:dawarich, Background, %{env: oidc})
    assert {:ok, _} = Background.page(scope)

    assert Background.update_visits(scope, %{"visits_suggestions_enabled" => "false"}) ==
             {:error, :oidc}

    Application.put_env(:dawarich, Background, %{
      env: %{"SELF_HOSTED" => "false"},
      oban: BackgroundDomainOban
    })

    assert Background.page(scope) == {:error, :cloud}
    assert Background.page(scope, %{"operator_authorized" => true}) == {:error, :cloud}

    System.put_env(%{
      "SIDEKIQ_USERNAME" => "synthetic-operator",
      "SIDEKIQ_PASSWORD" => "synthetic-password"
    })

    grant = String.duplicate("b", 43)
    operator = %{"operator_grant" => grant, "operator_login" => "synthetic-login"}
    assert {:ok, "OK"} = OperatorGrant.store(scope.user, "synthetic-login", grant)
    assert {:ok, _} = Background.page(scope, operator)

    for job <-
          ~w(start_immich_import start_photoprism_import start_airtrail_import start_teslamate_sync) do
      assert {:ok, _} = Background.request_job(scope, job, operator)
    end

    for job <- ~w(start_reverse_geocoding continue_reverse_geocoding),
        do: assert(Background.request_job(scope, job, operator) == {:error, :cloud})

    assert Background.update_visits(scope, %{"visits_suggestions_enabled" => "false"}) ==
             {:error, :cloud}

    assert Background.page(scope, Map.put(operator, "operator_login", "wrong")) ==
             {:error, :cloud}

    Application.put_env(:dawarich, Background, %{})

    for sql <- ["encrypted_password='changed-synthetic-password-salt'", "deleted_at=now()"] do
      Repo.query!("UPDATE users SET #{sql} WHERE id=10721", [], log: false)
      assert Background.page(scope) == {:error, :stale_session}
      assert Background.update_visits(scope, %{}) == {:error, :stale_session}
      assert Background.request_job(scope, "start_airtrail_import") == {:error, :stale_session}
    end

    assert Background.page(nil) == {:error, :stale_session}
    assert count("job_outbox") == 4 and count("oban.oban_jobs") == 0
  end

  defp count(table),
    do: Repo.query!("SELECT count(*) FROM #{table}", [], log: false).rows |> hd() |> hd()
end
