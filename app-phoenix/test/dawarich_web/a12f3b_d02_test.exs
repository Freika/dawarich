defmodule DawarichWeb.A12f3bD02Test do
  use ExUnit.Case, async: false
  import Plug.Conn
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.{AdminWritesGate, RailsCsrf}
  alias DawarichWeb.AdminWrites.Settings

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Repo.query!("DELETE FROM instance_settings", [], log: false)
    saved = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      if saved,
        do: System.put_env("DAWARICH_RAILS", saved),
        else: System.delete_env("DAWARICH_RAILS")
    end)

    for {id, admin} <- [{32001, true}, {32002, false}] do
      RailsUser.insert!(%{
        id: id,
        email: "admin-settings-#{id}@example.invalid",
        admin: admin,
        settings: %{"timezone" => "UTC", "locale" => "de"}
      })
    end

    %{
      context: %{
        self_hosted: true,
        oidc: false,
        env: %{},
        locale: "de",
        command: fn _ -> {:ok, 0} end
      }
    }
  end

  @tag a12f3b_case: "D02a"
  test "admin instance and background forms close native residual branches", c do
    for method <- ["PATCH", "PUT"] do
      conn =
        request(32001, method, "/admin/settings", [{"instance_settings[store_geodata]", "false"}])
        |> Settings.call(action: :instance, context: c.context)

      assert conn.status == 303

      assert Repo.query!("SELECT value FROM instance_settings WHERE key='store_geodata'", [],
               log: false
             ).rows == [[false]]
    end

    refute AdminWritesGate.eligible?(request(32002, "PATCH", "/admin/settings", []), :instance,
             context: c.context
           )

    assert {:handoff, :actor} =
             Dawarich.Admin.InstanceWrites.call(
               Accounts.get(32002),
               %{"instance_settings" => [{"store_geodata", "true"}]},
               c.context
             )

    conn =
      request(32001, "POST", "/admin/settings/test_geocoding", [])
      |> Settings.call(action: :test_geocoding, context: c.context)

    assert conn.status == 303
    assert get_resp_header(conn, "location") == ["http://www.example.com/admin/settings"]
    assert conn.private.dawarich_rails_session_changes["flash"]["flashes"]["alert"] != ""
    refute Map.has_key?(conn.private, :dawarich_proxy_owner)

    for {result, kind} <- [
          {:configured, "notice"},
          {:empty, "alert"},
          {:rate_limited, "alert"},
          {:failed, "alert"}
        ] do
      probe = fn _config, _coordinates, _options ->
        case result do
          :configured ->
            {:ok, [%{"properties" => %{"city" => "Synthetic", "country" => "Country"}}]}

          :empty ->
            {:ok, []}

          :rate_limited ->
            nil

          :failed ->
            {:error, :network}
        end
      end

      context =
        c.context
        |> Map.put(:env, %{"PHOTON_API_HOST" => "photon.example.invalid"})
        |> Map.put(:provider_test, probe)

      conn =
        request(32001, "POST", "/admin/settings/test_geocoding", [])
        |> Settings.call(action: :test_geocoding, context: context)

      assert conn.status == 303
      assert conn.private.dawarich_rails_session_changes["flash"]["flashes"][kind] != ""
    end

    conn =
      request(32002, "POST", "/admin/settings/test_geocoding", [])
      |> Settings.call(action: :test_geocoding, context: c.context)

    assert conn.status == 303
    assert Repo.query!("SELECT count(*) FROM job_outbox", [], log: false).rows == [[0]]
  end

  @tag a12f3b_case: "D02b"
  test "background settings dispatch every permitted source action natively", c do
    jobs = [
      {"start_immich_import", "imports.immich_geodata", "/imports"},
      {"start_photoprism_import", "imports.photoprism_geodata", "/imports"},
      {"start_airtrail_import", "imports.airtrail_flights", "/settings/integrations"},
      {"start_teslamate_sync", "imports.teslamate_sync",
       "/settings/integrations?service=teslamate"}
    ]

    for {job, type, path} <- jobs do
      Dawarich.Jobs.Ownership.put!(Repo, "command:" <> type, :oban)

      conn =
        request(32002, "POST", "/settings/background_jobs?job_name=" <> job, [])
        |> Settings.call(action: :background, context: c.context)

      assert conn.status == 302
      assert get_resp_header(conn, "location") == ["http://www.example.com" <> path]

      assert [[payload, metadata]] =
               Repo.query!(
                 "SELECT payload,metadata FROM job_outbox WHERE command_type=$1",
                 [type],
                 log: false
               ).rows

      assert payload["user_id"] == 32002
      assert metadata["locale"] == "de"
      assert metadata["time_zone"] == "Etc/UTC"

      if type in ["imports.immich_geodata", "imports.photoprism_geodata"],
        do: assert(payload["time_zone"] == "Etc/UTC")
    end

    conn =
      request(32002, "POST", "/settings/background_jobs", [{"job_name", "unknown"}])
      |> Settings.call(action: :background, context: c.context)

    assert conn.status == 422
    assert Repo.query!("SELECT count(*) FROM job_outbox", [], log: false).rows == [[4]]

    assert Repo.query!("SELECT count(*) FROM phoenix.rails_commands", [], log: false).rows == [
             [0]
           ]

    for {job, _, _} <- jobs do
      conn =
        request(32002, "POST", "/settings/background_jobs", [{"job_name", job}])
        |> Settings.call(action: :background, context: %{c.context | self_hosted: false})

      assert conn.status == 302
    end

    conn =
      request(32002, "PATCH", "/settings/background_jobs", [
        {"settings[visits_suggestions_enabled]", "false"}
      ])
      |> Settings.call(action: :background, context: c.context)

    assert conn.status == 302
    assert Accounts.settings(32002)["visits_suggestions_enabled"] == "false"
  end

  defp request(id, method, path, values) do
    session = RailsUser.session(id)
    raw = URI.encode_query([{"authenticity_token", RailsCsrf.masked_token(session)} | values])

    Plug.Test.conn(method, path, raw)
    |> Plug.Test.put_req_cookie("_dawarich_session", RailsUser.cookie(session))
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("content-length", Integer.to_string(byte_size(raw)))
    |> put_req_header("accept", "text/html")
  end
end

defmodule DawarichWeb.A12f3bD02GeocodingTest do
  use Dawarich.JobsCase
  alias Dawarich.Admin.{BackgroundCommands, BackgroundGeocodingWorker}
  alias Dawarich.Test.RailsUser

  setup do
    start_oban(AdminGeocodingOban)
    saved = System.get_env("PHOTON_API_HOST")
    System.put_env("PHOTON_API_HOST", "geocoding.example.invalid")

    on_exit(fn ->
      if saved,
        do: System.put_env("PHOTON_API_HOST", saved),
        else: System.delete_env("PHOTON_API_HOST")
    end)

    RailsUser.insert!(
      %{
        id: 32101,
        email: "background-geocoding@example.invalid",
        settings: %{"timezone" => "UTC"}
      },
      ScratchRepo
    )

    RailsUser.insert!(%{id: 32102, email: "foreign-geocoding@example.invalid"}, ScratchRepo)
    Dawarich.FixtureCleanup.delete!(ScratchRepo, ["public.points"])

    for {id, user, geocoded} <- [
          {32101, 32101, nil},
          {32102, 32101, NaiveDateTime.utc_now()},
          {32103, 32102, nil}
        ] do
      rows(
        "INSERT INTO points(id,user_id,timestamp,reverse_geocoded_at,created_at,updated_at) VALUES($1,$2,1,$3,now(),now())",
        [id, user, geocoded]
      )
    end

    Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:geocoding.reverse_point", :oban)

    %{
      context: %{
        repo: ScratchRepo,
        oban: AdminGeocodingOban,
        self_hosted: true,
        oidc: false,
        locale: "de"
      }
    }
  end

  @tag a12f3b_case: "D02c"
  test "background geocoding accepted retry publishes user batches once", c do
    assert {:ok, "/settings/background_jobs"} =
             BackgroundCommands.call(%{id: 32101}, "start_reverse_geocoding", c.context)

    assert [[id, args]] = rows("SELECT id,args FROM oban.oban_jobs")
    job = %Oban.Job{id: id, args: args, conf: %{name: AdminGeocodingOban}}
    assert :ok = BackgroundGeocodingWorker.perform(job)
    assert :ok = BackgroundGeocodingWorker.perform(job)

    assert rows("SELECT payload FROM job_outbox ORDER BY event_id") == [
             [%{"user_id" => 32101, "point_ids" => [32101, 32102], "force" => true}]
           ]

    assert {:ok, "/settings/background_jobs"} =
             BackgroundCommands.call(%{id: 32101}, "continue_reverse_geocoding", c.context)

    assert [[id, args]] = rows("SELECT id,args FROM oban.oban_jobs ORDER BY id DESC LIMIT 1")
    job = %Oban.Job{id: id, args: args, conf: %{name: AdminGeocodingOban}}
    assert :ok = BackgroundGeocodingWorker.perform(job)
    assert :ok = BackgroundGeocodingWorker.perform(job)
    assert rows("SELECT count(*) FROM job_outbox") == [[2]]

    assert rows("SELECT payload FROM job_outbox WHERE payload->>'force'='false'") == [
             [%{"user_id" => 32101, "point_ids" => [32101], "force" => false}]
           ]

    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
  end
end
