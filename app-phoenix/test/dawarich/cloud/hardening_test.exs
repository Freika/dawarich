defmodule Dawarich.Cloud.HardeningTest do
  use Dawarich.JobsCase, async: false
  import Dawarich.AnomalyCase
  import ExUnit.CaptureLog
  alias Dawarich.Cloud.ProviderHTTP
  alias Dawarich.Release.Cloud
  alias Dawarich.Jobs.Processed
  alias Dawarich.Users.{CreationWebhookWorker, DestructionWebhookWorker}
  alias Dawarich.Partnero.CustomerSignupWorker

  @env %{
    "SELF_HOSTED" => "false",
    "MANAGER_URL" => "https://manager.example.invalid",
    "JWT_SECRET_KEY" => "synthetic-hardening-key"
  }

  test "L1 hardening rejects plaintext Manager before any transport" do
    parent = self()

    transport = fn _, _, _, _, _, _, _, _ ->
      send(parent, :sent)
      {:ok, 200, [], ""}
    end

    for url <- ["http://manager.example.invalid", "http://127.0.0.1:1234"],
        path <- ["/api/v1/users", "/api/v1/users/unlink"] do
      assert {:error, :invalid_origin} =
               ProviderHTTP.post(:manager, path, [], "{}",
                 env: Map.put(@env, "MANAGER_URL", url),
                 transport: transport
               )
    end

    refute_received :sent

    assert {:ok, 200, ""} =
             ProviderHTTP.post(:partnero, "/v1/customers", [], "{}",
               env: %{"PARTNERO_URL" => "http://manager.example.invalid"},
               transport: transport
             )

    assert_receive :sent
  end

  test "L1 hardening loopback override is explicit and compiled out of production" do
    transport = fn _, _, _, _, _, false, _, _ -> {:ok, 200, [], ""} end
    opts = [test_loopback: true, transport: transport]

    assert {:ok, 200, ""} =
             ProviderHTTP.post(
               :manager,
               "/api/v1/users",
               [],
               "{}",
               Keyword.put(opts, :env, %{"MANAGER_URL" => "http://127.0.0.1:1234"})
             )

    assert {:error, :invalid_origin} =
             ProviderHTTP.post(
               :manager,
               "/api/v1/users",
               [],
               "{}",
               Keyword.put(opts, :env, %{"MANAGER_URL" => "http://manager.example.invalid"})
             )

    source =
      File.read!("lib/dawarich/cloud/provider_http.ex")
      |> String.replace(
        "defmodule Dawarich.Cloud.ProviderHTTP do",
        "defmodule Dawarich.Cloud.ProductionTransportProbe do"
      )

    previous = Application.get_env(:dawarich, :cloud_test_loopback)
    Application.put_env(:dawarich, :cloud_test_loopback, false)

    try do
      Code.compile_string(source)

      assert {:error, :invalid_origin} =
               apply(Dawarich.Cloud.ProductionTransportProbe, :post, [
                 :manager,
                 "/api/v1/users",
                 [],
                 "{}",
                 Keyword.put(opts, :env, %{
                   "MANAGER_URL" => "http://127.0.0.1:1234",
                   "DAWARICH_CLOUD_TEST_LOOPBACK" => "true"
                 })
               ])
    after
      Application.put_env(:dawarich, :cloud_test_loopback, previous)
      :code.purge(Dawarich.Cloud.ProductionTransportProbe)
      :code.delete(Dawarich.Cloud.ProductionTransportProbe)
    end
  end

  test "L1 hardening Cloud runtime boot and health refuse invalid config with safe operator messages" do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)

    previous =
      Map.new(
        ~w(SELF_HOSTED MANAGER_URL JWT_SECRET_KEY DAWARICH_RAILS),
        &{&1, System.get_env(&1)}
      )

    on_exit(fn -> restore(previous) end)
    System.put_env(@env)

    for key <- ~w(MANAGER_URL JWT_SECRET_KEY),
        blank <- [nil, "", " \t"],
        mode <- ["off", "proxy"] do
      set(key, blank)
      System.put_env("DAWARICH_RAILS", mode)

      assert_raise ArgumentError, ~r/Cloud configuration.*#{key}/, fn ->
        Config.Reader.read!("config/runtime.exs", env: :prod, target: :host)
      end

      logs =
        capture_log(fn ->
          for path <- ~w(/api/v1/ready /ready) do
            conn =
              Phoenix.ConnTest.dispatch(
                Phoenix.ConnTest.build_conn(),
                DawarichWeb.Endpoint,
                :get,
                path
              )

            assert conn.status == 503
            refute conn.resp_body =~ @env["JWT_SECRET_KEY"]
          end

          assert {:unavailable, :cloud_configuration} =
                   Dawarich.Readiness.check(
                     release: fn _ -> :ready end,
                     database: fn -> {:ok, %{rows: [[1]]}} end,
                     redis: fn -> {:ok, "PONG"} end
                   )
        end)

      assert logs =~ key
      refute logs =~ @env["JWT_SECRET_KEY"]
      System.put_env(@env)
    end

    System.put_env("MANAGER_URL", "http://manager.example.invalid")

    assert_raise ArgumentError, ~r/MANAGER_URL.*HTTPS/, fn ->
      Config.Reader.read!("config/runtime.exs", env: :prod, target: :host)
    end

    System.put_env("SELF_HOSTED", "true")
    System.delete_env("MANAGER_URL")
    System.delete_env("JWT_SECRET_KEY")
    assert is_list(Config.Reader.read!("config/runtime.exs", env: :prod, target: :host))
    assert Dawarich.Auth.RegistrationSetup.ready?(%{self_hosted: true})
  end

  test "L1 hardening provisioning readiness and signup refuse missing Cloud config" do
    rows("DELETE FROM public.data_migrations")

    rows("INSERT INTO public.data_migrations(version) SELECT unnest($1::text[])", [
      Dawarich.RailsTree.versions("data")
    ])

    rows("DELETE FROM public.ar_internal_metadata WHERE key='phoenix_native_baseline'")
    opts = [env: @env, command: fn _ -> {:ok, nil} end]
    assert :ok = Cloud.migrate(ScratchRepo, opts)
    assert Cloud.ready?(ScratchRepo, opts)

    for key <- ~w(MANAGER_URL JWT_SECRET_KEY), blank <- [nil, "", " \t"] do
      env = if blank, do: Map.put(@env, key, blank), else: Map.delete(@env, key)
      invalid = Keyword.put(opts, :env, env)
      assert {:error, {:cloud_configuration, message}} = Cloud.migrate(ScratchRepo, invalid)
      assert message =~ key
      refute Cloud.ready?(ScratchRepo, invalid)

      for channel <- [:browser, :mobile] do
        refute Dawarich.Auth.RegistrationSetup.ready?(%{
                 self_hosted: false,
                 registration_channel: channel,
                 env: env,
                 callbacks: %{webhook: fn _ -> :ok end}
               })
      end
    end
  end

  test "L1 hardening Manager config failures retain both callback receipts for repair" do
    user = user!()
    parent = self()

    transport = fn _, _, _, _, body, _, _, _ ->
      [header, payload, signature] = Jason.decode!(body)["token"] |> String.split(".")

      assert Base.url_decode64!(signature, padding: false) ==
               :crypto.mac(:hmac, :sha256, @env["JWT_SECRET_KEY"], header <> "." <> payload)

      send(parent, :sent)
      {:ok, 401, [], ""}
    end

    for worker <- [CreationWebhookWorker, DestructionWebhookWorker],
        key <- ~w(MANAGER_URL JWT_SECRET_KEY),
        blank <- [nil, "", " \t"] do
      args = %{
        "user_id" => user,
        "email" => "synthetic@example.invalid",
        "event_id" => Ecto.UUID.generate()
      }

      env = if blank, do: Map.put(@env, key, blank), else: Map.delete(@env, key)

      assert {:error, {:cloud_configuration, _}} =
               worker.run(ScratchRepo, args, env: env, transport: transport)

      refute Processed.done?(ScratchRepo, args["event_id"])
      refute_received :sent
      assert :ok = worker.run(ScratchRepo, args, env: @env, transport: transport)
      assert_receive :sent
      assert Processed.done?(ScratchRepo, args["event_id"])
    end
  end

  test "L1 hardening missing Partnero credentials retain attributed work without making Partnero mandatory" do
    user = user!()
    parent = self()

    transport = fn _, origin, _, _, _, _, _, _ ->
      assert origin == "https://api.partnero.com"
      send(parent, :sent)
      {:ok, 409, [], ""}
    end

    for blank <- [nil, "", " \t"] do
      args = %{
        "user_id" => user,
        "partner_key" => "synthetic-partner",
        "event_id" => Ecto.UUID.generate()
      }

      assert {:error, {:cloud_configuration, message}} =
               CustomerSignupWorker.run(ScratchRepo, args,
                 env: %{"PARTNERO_API_KEY" => blank},
                 transport: transport
               )

      assert message =~ "PARTNERO_API_KEY"
      refute Processed.done?(ScratchRepo, args["event_id"])
      refute_received :sent

      assert :ok =
               CustomerSignupWorker.run(ScratchRepo, args,
                 env: %{"PARTNERO_API_KEY" => "synthetic-key"},
                 transport: transport
               )

      assert_receive :sent
      assert Processed.done?(ScratchRepo, args["event_id"])
    end

    assert :ok = Dawarich.Cloud.Configuration.check(@env)
  end

  defp set(key, nil), do: System.delete_env(key)
  defp set(key, value), do: System.put_env(key, value)
  defp restore(env), do: Enum.each(env, fn {key, value} -> set(key, value) end)
end
