defmodule Dawarich.Release.CloudHandoffTest.Mail do
  def deliver(message, _env) do
    Agent.update(
      Application.fetch_env!(:dawarich, :l1_handoff_effects),
      &[{:mail, message.to} | &1]
    )

    send(Application.fetch_env!(:dawarich, :l1_handoff_receiver), {:mail, message})
    :ok
  end
end

defmodule Dawarich.Release.CloudHandoffTest do
  use Dawarich.ScratchCase, async: false
  alias Dawarich.Release.{Cloud, Lifecycle}
  alias Dawarich.Auth.{Registration, RegistrationSetup}
  alias Dawarich.Jobs.{Dispatch, Ownership, Processed}

  alias Dawarich.Users.{
    CreationEffects,
    CreationWebhookWorker,
    DestroyWorker,
    DestructionWebhookWorker
  }

  alias Dawarich.Partnero.CustomerSignupWorker
  alias Dawarich.ReleaseJobs.FamilyBackfill

  @oban __MODULE__.Oban
  @now ~U[2026-03-28 12:00:00.000000Z]
  @env %{
    "SELF_HOSTED" => "false",
    "DAWARICH_RAILS" => "off",
    "DAWARICH_PHOENIX_LIFECYCLE" => "true",
    "TIME_ZONE" => "Europe/Berlin",
    "MANAGER_URL" => "https://manager.example.invalid",
    "JWT_SECRET_KEY" => "synthetic-handoff",
    "PARTNERO_API_KEY" => "synthetic-partner",
    "DOMAIN" => "example.invalid",
    "SMTP_FROM" => "hello@example.invalid"
  }

  setup do
    previous = Map.new(Map.keys(@env), &{&1, System.get_env(&1)})

    saved =
      Map.new(
        [
          :jobs_repo,
          :mail_transport,
          :l1_handoff_receiver,
          :l1_handoff_effects,
          :user_webhook_http,
          :partnero_http
        ],
        &{&1, Application.get_env(:dawarich, &1)}
      )

    effects = start_supervised!({Agent, fn -> [] end})
    Application.put_env(:dawarich, :l1_handoff_effects, effects)
    System.put_env(@env)

    http = fn url, headers, body, _timeout ->
      uri = URI.parse(url)

      {:ok, status, _, response} =
        provider(:post, "#{uri.scheme}://#{uri.host}", uri.path, headers, body, false, 10_000,
          total_timeout: 10_000
        )

      {:ok, status, response}
    end

    Application.put_env(:dawarich, :user_webhook_http, http)
    Application.put_env(:dawarich, :partnero_http, http)
    Application.put_env(:dawarich, :jobs_repo, ScratchRepo)
    Application.put_env(:dawarich, :mail_transport, __MODULE__.Mail)
    Application.put_env(:dawarich, :l1_handoff_receiver, self())
    for schema <- ~w(phoenix oban), do: sql("DROP SCHEMA IF EXISTS #{schema} CASCADE")
    Dawarich.MigrationModules.purge()
    for extension <- ~w(pgcrypto postgis), do: sql("CREATE EXTENSION IF NOT EXISTS #{extension}")
    for schema <- ~w(phoenix oban), do: sql("CREATE SCHEMA #{schema}")
    for spec <- Dawarich.Redis.cache_child_specs(), do: start_supervised!(spec)

    on_exit(fn ->
      for {key, value} <- previous do
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end

      for {key, value} <- saved do
        if value,
          do: Application.put_env(:dawarich, key, value),
          else: Application.delete_env(:dawarich, key)
      end

      Dawarich.ScratchCase.recreate_public!(ScratchRepo)
      Dawarich.MigrationModules.purge()
      Dawarich.Release.install_schemas(ScratchRepo)
    end)

    :ok
  end

  test "L1 handoff self-hosted creation and registration send no Cloud callbacks" do
    assert :ok = Cloud.migrate(ScratchRepo, opts())
    start_jobs()
    cloud_keys = ~w(SELF_HOSTED DAWARICH_RAILS DAWARICH_PHOENIX_LIFECYCLE)
    env = Map.drop(@env, cloud_keys)
    for key <- cloud_keys, do: System.delete_env(key)

    ctx =
      context()
      |> Map.delete(:self_hosted)
      |> Map.put(:env, env)
      |> Map.put(:registration_enabled, true)
      |> Map.put(:oidc, false)

    assert {:ok, result} =
             Registration.register(
               %{
                 "email" => "signup@example.invalid",
                 "password" => "synthetic-password",
                 "password_confirmation" => "synthetic-password"
               },
               %{"partnero_referral" => "synthetic-referral"},
               ctx
             )

    assert result.signed_in
    assert result.location == "/"
    assert result.session["partnero_referral"] == "synthetic-referral"
    ordinary = ordinary!(env)

    for id <- [result.user.id, ordinary] do
      assert sql("SELECT status,length(api_key),active_until > $2 FROM users WHERE id=$1", [
               id,
               DateTime.to_naive(@now)
             ]) == [[1, 64, true]]

      assert Processed.done?(
               ScratchRepo,
               Dawarich.AfterCommit.identity(id, "users.creation_effects")
             )
    end

    assert sql("SELECT command_type FROM job_outbox") == []
    assert dispatch() == %{}

    for worker <- [
          CreationWebhookWorker,
          CustomerSignupWorker,
          Dawarich.Mail.WelcomeWorker,
          Dawarich.Mail.ExploreFeaturesWorker
        ],
        do: deliver(worker)

    assert effects() == []
    refute_received {:provider, _, _}
    refute_received {:mail, _}
  end

  test "L1 handoff provisions schema-owner Cloud and delivers each callback to its own user" do
    role = "l1_handoff_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
    sql("CREATE ROLE #{role} LOGIN PASSWORD 'synthetic-handoff-role'")
    for schema <- ~w(public phoenix oban), do: sql("ALTER SCHEMA #{schema} OWNER TO #{role}")

    pool =
      start_supervised!(
        {ScratchRepo,
         name: nil, pool_size: 3, username: role, password: "synthetic-handoff-role"},
        id: :role
      )

    on_exit(fn ->
      sql("DROP OWNED BY #{role} CASCADE")
      sql("DROP ROLE #{role}")
      for schema <- ~w(public phoenix oban), do: sql("CREATE SCHEMA IF NOT EXISTS #{schema}")
    end)

    old = ScratchRepo.get_dynamic_repo()

    try do
      ScratchRepo.put_dynamic_repo(pool)

      assert sql("SELECT has_database_privilege(current_user,current_database(),'CREATE')") == [
               [false]
             ]

      assert :ok = Cloud.migrate(ScratchRepo, opts())
      assert :ok = Cloud.seed(ScratchRepo, opts())
      assert sql("SELECT count(*) FROM users") == [[0]]
      assert Cloud.ready?(ScratchRepo, opts())

      for table <-
            ~w(public.schema_migrations phoenix.phoenix_schema_migrations oban.phoenix_schema_migrations),
          do: assert(sql("SELECT count(*) > 0 FROM #{table}") == [[true]])
    after
      ScratchRepo.put_dynamic_repo(old)
    end

    start_jobs()
    user = signup()

    assert sql("SELECT status,active_until,length(api_key) FROM users WHERE id=$1", [user.id]) ==
             [[3, nil, 64]]

    assert sql("SELECT command_type FROM job_outbox ORDER BY command_type") == [
             ["partnero.customer_signup"],
             ["users.creation_webhook"]
           ]

    dispatch()
    deliver(CreationWebhookWorker)
    deliver(CustomerSignupWorker)
    assert_receive {:provider, "/api/v1/users", %{"action" => "create_user", "user_id" => id}}
    assert id == user.id

    assert_receive {:provider, "/v1/customers",
                    %{"key" => key, "partner" => %{"key" => "synthetic-referral"}}}

    assert key == Integer.to_string(user.id)
    ordinary = ordinary!()
    dispatch()
    deliver(CreationWebhookWorker)

    assert_receive {:provider, "/api/v1/users",
                    %{
                      "action" => "create_user",
                      "user_id" => ^ordinary,
                      "email" => "ordinary@example.invalid"
                    }}

    deliver(Dawarich.Mail.WelcomeWorker)
    assert_receive {:mail, %{to: "ordinary@example.invalid"}}

    assert sql("SELECT status,active_until FROM users WHERE id=$1", [ordinary]) == [
             [2, ~N[2026-04-04 11:00:00.000000]]
           ]

    assert sql(
             "SELECT scheduled_at AT TIME ZONE 'UTC' FROM job_outbox WHERE command_type='users.explore_features_mail'"
           ) == [[~N[2026-03-30 11:00:00.000000]]]

    sql(
      "UPDATE job_outbox SET scheduled_at=now() WHERE command_type='users.explore_features_mail'"
    )

    dispatch()
    deliver(Dawarich.Mail.ExploreFeaturesWorker)
    assert_receive {:mail, %{to: "ordinary@example.invalid"}}
    backfill(user.id)
    delete(ordinary)

    assert_receive {:provider, "/api/v1/users/unlink",
                    %{"user_id" => ^ordinary, "action" => "destroy_user"}}

    assert_effects(user.id, ordinary, 2, true)

    assert_handoff("ED-552")
  end

  test "L1 handoff reentry preserves trial family mail referral and unlink identities" do
    source!()
    historical = sql("SELECT id,status,plan,active_until,api_key FROM users")
    assert :ok = Cloud.migrate(ScratchRepo, opts())
    assert sql("SELECT id,status,plan,active_until,api_key FROM users") == historical
    start_jobs()
    user = signup()
    ordinary = ordinary!()
    dispatch()
    creation = args(CreationWebhookWorker) |> Enum.find(&(&1["user_id"] == user.id))
    transport = fn _, _, _, _, _, _, _, _ -> {:error, :timeout} end

    assert {:error, _} =
             CreationWebhookWorker.run(ScratchRepo, creation,
               env: @env,
               http: fn _, _, _, _ -> {:error, :timeout} end,
               transport: transport
             )

    refute Processed.done?(ScratchRepo, creation["event_id"])
    deliver(CreationWebhookWorker)
    deliver(CustomerSignupWorker)
    deliver(Dawarich.Mail.WelcomeWorker)
    assert_effects(user.id, ordinary, 1)
    assert_receive {:mail, %{to: "ordinary@example.invalid"}}
    backfill(user.id)
    before = snapshot()
    sent = effects()

    for _ <- 1..2 do
      assert :ok = Cloud.migrate(ScratchRepo, opts())
      assert :ok = Cloud.seed(ScratchRepo, opts())
      assert {:ok, _} = RegistrationSetup.complete(user, %{}, %{}, context())

      assert {:ok, :ok} =
               ScratchRepo.transaction(fn ->
                 CreationEffects.apply(ScratchRepo, ordinary, env: @env, now: @now)
               end)

      deliver(CreationWebhookWorker)
      deliver(CustomerSignupWorker)
      deliver(Dawarich.Mail.WelcomeWorker)
      assert snapshot() == before
      assert effects() == sent
    end

    refute_received {:mail, _}
    delete(ordinary)
    assert_effects(user.id, ordinary, 1, true)

    [[unlink]] =
      sql("SELECT event_id::text FROM job_outbox WHERE command_type='users.destruction_webhook'")

    sent = effects()
    receipts = sql("SELECT count(*) FROM phoenix.processed_commands")
    deliver(DestructionWebhookWorker)
    assert sql("SELECT count(*) FROM phoenix.processed_commands") == receipts
    assert effects() == sent
    assert Processed.done?(ScratchRepo, unlink)
    sql("DELETE FROM job_outbox WHERE command_type='users.destruction_webhook'")

    [[root]] =
      sql("SELECT args FROM oban.oban_jobs WHERE worker=$1", [
        Oban.Worker.to_string(DestroyWorker)
      ])

    assert :ok = DestroyWorker.run(ScratchRepo, root)

    assert sql("SELECT count(*) FROM job_outbox WHERE command_type='users.destruction_webhook'") ==
             [[0]]

    {:ok, FamilyBackfill, pending} =
      Dawarich.ReleaseJobs.decode("DataMigrations::BackfillFamiliesForFamilyPlanJob", [])

    sql(
      "INSERT INTO phoenix.release_operations(id,command_type,cursor,status) VALUES($1,$2,$3,'failed')",
      [Ecto.UUID.dump!(pending["operation_id"]), FamilyBackfill.command_type(), pending["cursor"]]
    )

    refute Cloud.ready?(ScratchRepo, opts())
    assert :ok = FamilyBackfill.perform(%Oban.Job{args: pending, conf: Oban.config(@oban)})
    assert Cloud.ready?(ScratchRepo, opts())
    assert Lifecycle.mode(@env) == {:error, :cloud_native_lifecycle}
    assert_handoff("Remote acceptance")
  end

  defp opts, do: [env: @env, command: fn _ -> {:ok, nil} end, now: @now]
  defp sql(query, params \\ []), do: ScratchRepo.query!(query, params, log: false).rows

  defp context,
    do: %{repo: ScratchRepo, self_hosted: false, env: @env, clock: fn -> @now end, log_rounds: 4}

  defp start_jobs do
    start_supervised!(
      {Oban,
       name: @oban,
       repo: ScratchRepo,
       prefix: "oban",
       notifier: Oban.Notifiers.PG,
       testing: :manual}
    )

    for type <-
          ~w(users.creation_webhook users.destruction_webhook partnero.customer_signup mail.user.welcome users.explore_features_mail users.destroy release.family_backfill),
        do: Ownership.put!(ScratchRepo, "command:" <> type, :oban)
  end

  defp signup do
    params = %{
      "email" => "signup@example.invalid",
      "password" => "synthetic-password",
      "password_confirmation" => "synthetic-password"
    }

    assert {:ok, result} =
             Registration.register(
               params,
               %{"partnero_referral" => "synthetic-referral"},
               context()
             )

    refute Map.has_key?(result.session, "partnero_referral")
    result.user
  end

  defp ordinary!(env \\ @env) do
    user =
      Dawarich.Test.RailsUser.insert!(
        %{
          id: System.unique_integer([:positive]),
          email: "ordinary@example.invalid",
          active_until: nil,
          status: 0
        },
        ScratchRepo
      )

    assert {:ok, :ok} =
             ScratchRepo.transaction(fn ->
               CreationEffects.apply(ScratchRepo, user.id, env: env, now: @now)
             end)

    user.id
  end

  defp dispatch, do: Dispatch.run(repo: ScratchRepo, oban: @oban)

  defp args(worker),
    do:
      sql("SELECT args FROM oban.oban_jobs WHERE worker=$1 ORDER BY id", [
        Oban.Worker.to_string(worker)
      ])
      |> List.flatten()

  defp deliver(worker) do
    for args <- args(worker) do
      result =
        case worker do
          CreationWebhookWorker ->
            worker.run(ScratchRepo, args, env: @env, transport: &provider/8)

          CustomerSignupWorker ->
            worker.run(ScratchRepo, args, env: @env, transport: &provider/8)

          DestructionWebhookWorker ->
            worker.run(ScratchRepo, args, env: @env, transport: &provider/8)

          _ ->
            worker.perform(%Oban.Job{args: args})
        end

      assert result == :ok
    end
  end

  defp provider(:post, origin, path, _headers, body, false, 10_000, opts) do
    refute ScratchRepo.in_transaction?()
    assert opts[:total_timeout] == 10_000

    assert origin ==
             if(path == "/v1/customers",
               do: "https://api.partnero.com",
               else: @env["MANAGER_URL"]
             )

    payload = Jason.decode!(body)

    payload =
      if token = payload["token"] do
        [_header, data, _signature] = String.split(token, ".")
        data |> Base.url_decode64!(padding: false) |> Jason.decode!()
      else
        payload
      end

    Agent.update(
      Application.fetch_env!(:dawarich, :l1_handoff_effects),
      &[{path, {payload["user_id"] || payload["key"], payload["action"]}} | &1]
    )

    send(Application.fetch_env!(:dawarich, :l1_handoff_receiver), {:provider, path, payload})
    {:ok, 201, [], ""}
  end

  defp backfill(id) do
    sql("UPDATE users SET plan=2,active_until='2099-01-01' WHERE id=$1", [id])

    for class <-
          ~w(DataMigrations::BackfillFamiliesForFamilyPlanJob DataMigrations::BackfillFamilyMemberEntitlementsJob) do
      {:ok, FamilyBackfill, args} = Dawarich.ReleaseJobs.decode(class, [])

      if args["cursor"]["phase"] == "entitlements" do
        [[family]] = sql("SELECT id FROM families WHERE creator_id=$1", [id])

        member =
          Dawarich.Test.RailsUser.insert!(
            %{
              id: System.unique_integer([:positive]),
              email: "member@example.invalid",
              plan: 0,
              status: 0,
              active_until: nil
            },
            ScratchRepo
          )

        sql(
          "INSERT INTO family_memberships(family_id,user_id,role,created_at,updated_at) VALUES($1,$2,1,now(),now())",
          [family, member.id]
        )
      end

      assert {:ok, :ok} =
               ScratchRepo.transaction(fn ->
                 Dawarich.AfterCommit.intent(
                   ScratchRepo,
                   FamilyBackfill.command_type(),
                   args["cursor"],
                   event_id: args["operation_id"]
                 )
               end)

      assert %{dispatched: 1} = dispatch()

      assert %{failure: 0, discard: 0} =
               Oban.drain_queue(@oban,
                 queue: :maintenance,
                 with_recursion: true,
                 with_scheduled: true
               )
    end

    assert sql("SELECT count(*) FROM families WHERE creator_id=$1", [id]) == [[1]]

    assert sql("SELECT plan,status,active_until FROM users WHERE email='member@example.invalid'") ==
             [[1, 1, ~N[2099-01-01 00:00:00.000000]]]
  end

  defp delete(id) do
    root = Ecto.UUID.generate()
    sql("UPDATE users SET deleted_at=now() WHERE id=$1", [id])

    assert {:ok, :ok} =
             ScratchRepo.transaction(fn -> DestroyWorker.enqueue(ScratchRepo, id, root) end)

    dispatch()
    for args <- args(DestroyWorker), do: assert(:ok == DestroyWorker.run(ScratchRepo, args))
    dispatch()
    deliver(DestructionWebhookWorker)
    assert sql("SELECT id FROM users WHERE id=$1", [id]) == []
  end

  defp effects, do: Agent.get(Application.fetch_env!(:dawarich, :l1_handoff_effects), & &1)

  defp assert_effects(signup, ordinary, mails, unlinked \\ false) do
    expected = %{
      {"/api/v1/users", {signup, "create_user"}} => 1,
      {"/api/v1/users", {ordinary, "create_user"}} => 1,
      {"/v1/customers", {Integer.to_string(signup), nil}} => 1,
      {:mail, "ordinary@example.invalid"} => mails
    }

    expected =
      if unlinked,
        do: Map.put(expected, {"/api/v1/users/unlink", {ordinary, "destroy_user"}}, 1),
        else: expected

    assert Enum.frequencies(effects()) == expected
  end

  defp snapshot do
    for table <-
          ~w(users families family_memberships job_outbox phoenix.processed_commands phoenix.release_operations) do
      {table,
       sql(
         "SELECT md5(coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text)::text,'')) FROM #{table} t"
       )}
    end
  end

  defp assert_handoff(needle) do
    path = Path.expand("../../../../docs/phoenix/l1-cloud-rollout.md", __DIR__)
    assert File.exists?(path), "external L1 handoff document is missing"
    assert File.read!(path) =~ needle
    register = File.read!(Path.expand("../../../parity/expected_diffs.md", __DIR__))
    assert register =~ "| ED-552 | Ordinary Cloud demo administrator bootstrap |"
    assert register =~ "Eugene ruling 2026-10-07"
  end

  defp source! do
    config = ScratchRepo.config()

    code =
      "Rails.logger=Logger.new(File::NULL); ActiveRecord::Schema.verbose=false; load Rails.root.join('db/schema.rb'); User.reset_column_information; User.create!(email: 'historical@example.invalid', password: 'synthetic-password', password_confirmation: 'synthetic-password', skip_auto_trial: true, skip_family_sync: true, status: :active, plan: :pro, api_key: 'synthetic-existing', active_until: Time.utc(2030,1,1)); puts 'L1-SOURCE-OK'"

    {output, status} =
      System.cmd(
        System.find_executable("asdf"),
        ["exec", "bundle", "exec", "rails", "runner", code],
        cd: Application.fetch_env!(:dawarich, :rails_root),
        env: [
          {"RAILS_ENV", "test"},
          {"DATABASE_NAME", config[:database]},
          {"DATABASE_HOST", "127.0.0.1"},
          {"REDIS_URL", Application.fetch_env!(:dawarich, :redis)[:url]},
          {"MANAGER_URL", ""},
          {"PARTNERO_API_KEY", ""},
          {"DAWARICH_RAILS", "on"},
          {"DAWARICH_PHOENIX_LIFECYCLE", "false"}
        ],
        stderr_to_stdout: true
      )

    assert status == 0, "source fixture refused"
    assert output =~ "L1-SOURCE-OK"
    sql("DELETE FROM data_migrations")

    sql("INSERT INTO data_migrations(version) SELECT unnest($1::text[])", [
      Dawarich.RailsTree.versions("data")
    ])
  end
end
