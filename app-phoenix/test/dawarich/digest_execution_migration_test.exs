defmodule Dawarich.DigestExecutionMigrationTest do
  use ExUnit.Case, async: false

  defmodule Repo do
    use Ecto.Repo, otp_app: :dawarich, adapter: Ecto.Adapters.Postgres
  end

  @migration Path.expand(
               "../../priv/repo/migrations/20261007235900_create_digest_executions.exs",
               __DIR__
             )

  for source <- [:with_outbox, :rails_alone] do
    @tag a12f3b_case: if(source == :with_outbox, do: "RX29", else: "RX31")
    test if(source == :with_outbox,
           do:
             "RX29 additive migration creates period state before reconciling Rails public results",
           else: "RX31 additive migration reconciles Rails public results without native outbox"
         ) do
      prepare_database!()

      if unquote(source) == :rails_alone,
        do: Repo.query!("DROP TABLE public.job_outbox", [], log: false)

      source = File.read!(@migration)

      [{module, _}] =
        Code.compile_string(
          String.replace(
            source,
            "Dawarich.Repo.Migrations.CreateDigestExecutions",
            "Dawarich.TestDigestPeriodMigration"
          )
        )

      assert :ok =
               Ecto.Migrator.up(Repo, 20_261_007_235_900, module, prefix: "phoenix", log: false)

      assert Repo.query!(
               "SELECT effect,state,outcome FROM phoenix.digest_executions ORDER BY effect",
               [],
               log: false
             ).rows == [
               ["digests.calculate_month", "generated", "mail"],
               ["digests.calculate_year", "published", "mail"]
             ]

      assert Repo.query!("SELECT count(*) FROM public.digests", [], log: false).rows == [[2]]
    end
  end

  for access <- [:schema_denied, :select_denied] do
    @tag a12f3b_case: "RX30"
    test "RX30 upgrade skips unreadable public sources #{access}" do
      prepare_database!()
      [_, ddl] = Regex.run(~r/execute\("""\n(.*?)\n    """\)/s, File.read!(@migration))
      Repo.query!(ddl, [], log: false)
      role = "digest_upgrade_" <> String.replace(Ecto.UUID.generate(), "-", "")
      Repo.query!("CREATE ROLE #{role} NOLOGIN", [], log: false)

      try do
        Repo.query!("GRANT USAGE ON SCHEMA phoenix TO #{role}", [], log: false)
        Repo.query!("GRANT ALL ON ALL TABLES IN SCHEMA phoenix TO #{role}", [], log: false)
        Repo.query!("REVOKE USAGE ON SCHEMA public FROM PUBLIC", [], log: false)

        if unquote(access) == :select_denied,
          do: Repo.query!("GRANT USAGE ON SCHEMA public TO #{role}", [], log: false)

        assert {:ok, :ok} =
                 Repo.transaction(fn ->
                   Repo.query!("SET LOCAL ROLE #{role}", [], log: false)

                   assert Repo.query!("SELECT has_schema_privilege('public','USAGE')", [],
                            log: false
                          ).rows ==
                            [[unquote(access) == :select_denied]]

                   if unquote(access) == :select_denied,
                     do:
                       assert(
                         Repo.query!("SELECT has_table_privilege('public.digests','SELECT')", [],
                           log: false
                         ).rows == [[false]]
                       )

                   Dawarich.Digests.ExecutionUpgrade.backfill(Repo)
                 end)
      after
        Repo.query!("DROP OWNED BY #{role}", [], log: false)
        Repo.query!("DROP ROLE #{role}", [], log: false)
      end
    end
  end

  defp prepare_database! do
    config = Dawarich.ScratchRepo.config()
    database = config[:database] <> "_dg"
    config = Keyword.put(config, :database, database)
    previous = Application.get_env(:dawarich, Repo)
    Application.put_env(:dawarich, Repo, config)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:dawarich, Repo, previous),
        else: Application.delete_env(:dawarich, Repo)
    end)

    case Ecto.Adapters.Postgres.storage_up(config) do
      result when result in [:ok, {:error, :already_up}] -> :ok
      _ -> flunk("private migration database setup failed")
    end

    start_supervised!({Repo, config})
    assert Repo.query!("SELECT current_database()", [], log: false).rows == [[database]]
    Repo.query!("DROP SCHEMA IF EXISTS phoenix CASCADE", [], log: false)
    Repo.query!("DROP SCHEMA public CASCADE", [], log: false)
    Repo.query!("CREATE SCHEMA public; CREATE SCHEMA phoenix", [], query_type: :text, log: false)

    Repo.query!(
      """
      CREATE TABLE public.digests(user_id bigint,year integer,month integer,period_type integer,sent_at timestamptz);
      CREATE TABLE public.job_outbox(event_id uuid,command_type text,payload jsonb);
      CREATE TABLE phoenix.rails_commands(id bigserial,kind text,payload jsonb);
      CREATE TABLE phoenix.processed_commands(event_id uuid,handler text,processed_at timestamptz);
      INSERT INTO public.digests VALUES(1,2025,3,0,NULL),(1,2025,NULL,1,now())
      """,
      [],
      query_type: :text,
      log: false
    )
  end
end
