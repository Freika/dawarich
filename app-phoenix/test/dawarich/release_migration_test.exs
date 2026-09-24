defmodule Dawarich.ReleaseMigrationTest do
  use Dawarich.ScratchCase

  import Dawarich.ReleaseMigration

  alias Dawarich.ReleaseMigration.UnportedEffect

  test "the connection runs in UTC like a Rails session" do
    assert %{rows: [["UTC"]]} = ScratchRepo.query!("SHOW timezone")
  end

  test "sql! runs several statements in one call inside the caller's transaction" do
    assert {:error, :undo} =
             ScratchRepo.transaction(fn ->
               sql!(ScratchRepo, "CREATE TABLE probe_a (id int); CREATE TABLE probe_b (id int);")
               assert table?(ScratchRepo, "probe_a")
               assert table?(ScratchRepo, "probe_b")
               ScratchRepo.rollback(:undo)
             end)

    refute table?(ScratchRepo, "probe_a")
  end

  test "outside a transaction sql! runs exactly one statement, quotes and $$ bodies aside" do
    assert_raise ArgumentError, ~r/one statement per sql!/, fn ->
      sql!(ScratchRepo, "CREATE TABLE probe_a (id int); CREATE TABLE probe_b (id int);")
    end

    refute table?(ScratchRepo, "probe_a")

    for sql <- [
          "-- it's the first\nCREATE TABLE probe_d (id int);\n-- it's the second\nCREATE TABLE probe_e (id int);",
          "/* it's */ CREATE TABLE probe_d (id int); /* it's */ CREATE TABLE probe_e (id int);",
          ~S"CREATE TABLE probe_d (note text DEFAULT E'it\'s'); CREATE TABLE probe_e (note text DEFAULT 'x');",
          ~S|CREATE TABLE "o'neil" (id int); CREATE TABLE probe_e (note text DEFAULT 'x');|,
          "CREATE TABLE probe_d (note text DEFAULT '$$'); CREATE TABLE probe_e (note text DEFAULT '$$');"
        ] do
      assert_raise ArgumentError, ~r/one statement per sql!/, fn -> sql!(ScratchRepo, sql) end
    end

    refute table?(ScratchRepo, "probe_e")

    assert_raise ArgumentError, ~r/cannot count the statements/, fn ->
      sql!(ScratchRepo, "SELECT 'unterminated")
    end

    assert sql!(ScratchRepo, "CREATE TABLE probe_c (note text DEFAULT 'a;b');") == :ok

    assert sql!(ScratchRepo, """
           DO $$ BEGIN IF NOT EXISTS (SELECT 1) THEN RAISE NOTICE 'x'; END IF; END $$;
           """) == :ok
  end

  test "catalog checks answer like Rails' existence checks" do
    scratch_sql!("""
    CREATE TABLE probe (id bigserial primary key, user_id bigint, name text);
    CREATE UNIQUE INDEX probe_user_name ON probe (user_id, name);
    CREATE INDEX probe_user_lower_name ON probe (user_id, lower(name));
    CREATE VIEW probe_view AS SELECT 1 AS one;
    """)

    assert table?(ScratchRepo, "probe")
    refute table?(ScratchRepo, "probe_view")
    refute table?(ScratchRepo, "missing")
    assert column?(ScratchRepo, "probe", "name")
    refute column?(ScratchRepo, "probe", "missing")
    assert_raise Postgrex.Error, fn -> column?(ScratchRepo, "missing", "id") end
    assert index?(ScratchRepo, "probe", name: "probe_user_name", columns: ["user_id", "name"])
    refute index?(ScratchRepo, "probe", name: "probe_user_name", columns: ["name"])
    refute index?(ScratchRepo, "probe", columns: ["user_id"])
    refute index?(ScratchRepo, "probe", name: "probe_pkey")
    assert index_name?(ScratchRepo, "probe", "probe_pkey")
    assert index_name?(ScratchRepo, "probe", "probe_user_lower_name")
    refute index_name?(ScratchRepo, "probe", "missing")

    assert_raise ArgumentError, fn ->
      index?(ScratchRepo, "probe", name: "probe_user_name", unique: true)
    end
  end

  test "index? compares key columns only, leaving INCLUDE columns out like Rails" do
    scratch_sql!("""
    CREATE TABLE probe (id bigint, user_id bigint, name text);
    CREATE INDEX probe_name_include ON probe (name) INCLUDE (user_id);
    """)

    assert index?(ScratchRepo, "probe", name: "probe_name_include", columns: ["name"])
    refute index?(ScratchRepo, "probe", columns: ["name", "user_id"])
  end

  test "normalize/1 reads the step's transaction flag" do
    fun = fn _repo -> :ok end
    assert normalize({"20990101000001", fun}) == {"20990101000001", fun, true}

    assert normalize({"20990101000001", fun, transaction: false}) ==
             {"20990101000001", fun, false}
  end

  test "with_lock_retry runs its block in a transaction with a local lock_timeout" do
    sql!(ScratchRepo, "CREATE TABLE probe (id int)")

    ScratchRepo.checkout(fn ->
      assert :acquired =
               with_lock_retry(
                 ScratchRepo,
                 fn -> sql!(ScratchRepo, "ALTER TABLE probe ADD COLUMN x int") end,
                 lock_timeout: "1s",
                 attempts: 1,
                 backoff_seconds: 0
               )

      assert %{rows: [["0"]]} = ScratchRepo.query!("SHOW lock_timeout")
    end)

    assert column?(ScratchRepo, "probe", "x")
  end

  test "with_lock_retry gives up after its attempts while another session uses the table" do
    sql!(ScratchRepo, "CREATE TABLE probe (id int)")
    parent = self()

    holder =
      Task.async(fn ->
        ScratchRepo.transaction(fn ->
          ScratchRepo.query!("SELECT 1 FROM probe")
          send(parent, :holding)

          receive do
            :release -> :ok
          end
        end)
      end)

    assert_receive :holding, 5_000

    assert {:not_acquired,
            %Postgrex.Error{postgres: %{code: :lock_not_available, pg_code: "55P03"}}} =
             with_lock_retry(
               ScratchRepo,
               fn -> sql!(ScratchRepo, "ALTER TABLE probe ADD COLUMN x int") end,
               lock_timeout: "50ms",
               attempts: 2,
               backoff_seconds: 0
             )

    send(holder.pid, :release)
    Task.await(holder)
    refute column?(ScratchRepo, "probe", "x")
  end

  test "with_lock_retry and rescue_sql refuse to run inside a transaction" do
    assert_raise ArgumentError, fn ->
      ScratchRepo.transaction(fn ->
        with_lock_retry(ScratchRepo, fn -> :ok end,
          lock_timeout: "1s",
          attempts: 1,
          backoff_seconds: 0
        )
      end)
    end

    assert_raise ArgumentError, fn ->
      ScratchRepo.transaction(fn -> rescue_sql(ScratchRepo, fn -> :ok end, :any, & &1) end)
    end
  end

  test "rescue_sql falls back only on the listed Postgres error codes" do
    scratch_sql!("CREATE TABLE probe (id int); INSERT INTO probe VALUES (1), (1);")

    assert :fallback =
             rescue_sql(
               ScratchRepo,
               fn -> sql!(ScratchRepo, "CREATE UNIQUE INDEX probe_id ON probe (id)") end,
               [:unique_violation],
               fn _error -> :fallback end
             )

    assert_raise Postgrex.Error, fn ->
      rescue_sql(
        ScratchRepo,
        fn -> sql!(ScratchRepo, "SELECT * FROM missing") end,
        [:unique_violation],
        fn _error -> :fallback end
      )
    end

    assert :any =
             rescue_sql(
               ScratchRepo,
               fn -> sql!(ScratchRepo, "SELECT * FROM missing") end,
               :any,
               fn _error -> :any end
             )
  end

  test "require_zero_lock_timeout! names the setting CREATE INDEX CONCURRENTLY needs" do
    assert require_zero_lock_timeout!(ScratchRepo) == :ok

    assert_raise RuntimeError, ~r/lock_timeout is 1s/, fn ->
      ScratchRepo.transaction(fn ->
        ScratchRepo.query!("SET LOCAL lock_timeout = '1s'")
        require_zero_lock_timeout!(ScratchRepo)
      end)
    end
  end

  test "unported! stops the step with the effect's name" do
    assert_raise UnportedEffect, "Achievements::LoadRegions has no Phoenix port yet", fn ->
      unported!("Achievements::LoadRegions")
    end
  end

  test "job/3 builds the spec a step returns" do
    assert job("DataMigrations::ProbeJob") == {"DataMigrations::ProbeJob", [], 0}
    assert job("Tracks::DeduplicationJob", [7], 300) == {"Tracks::DeduplicationJob", [7], 300}
  end

  test "self_hosted? parses SELF_HOSTED like config/initializers/01_constants.rb:5" do
    original = System.get_env("SELF_HOSTED")

    on_exit(fn ->
      if original,
        do: System.put_env("SELF_HOSTED", original),
        else: System.delete_env("SELF_HOSTED")
    end)

    for {value, expected} <- [
          {nil, true},
          {"false", false},
          {"'yes'", true},
          {" 1 ", true},
          {"\"T\"", true},
          {"no", false}
        ] do
      if value, do: System.put_env("SELF_HOSTED", value), else: System.delete_env("SELF_HOSTED")
      assert self_hosted?() == expected, inspect(value)
    end
  end
end
