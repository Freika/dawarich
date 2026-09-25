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

  test "index_names lists the table's indexes on exactly these key columns by name, as Rails' index_name_for_remove matches them" do
    scratch_sql!("""
    CREATE TABLE probe (id bigserial primary key, user_id bigint, name text);
    CREATE TABLE other (user_id bigint);
    CREATE INDEX probe_z_user ON probe (user_id);
    CREATE INDEX probe_a_user ON probe (user_id) WHERE name IS NOT NULL;
    CREATE INDEX probe_user_name ON probe (user_id, name);
    CREATE INDEX probe_name_include ON probe (name) INCLUDE (user_id);
    CREATE INDEX probe_lower_name ON probe (lower(name));
    CREATE INDEX other_user ON other (user_id);
    """)

    assert index_names(ScratchRepo, "probe", ["user_id"]) == ["probe_a_user", "probe_z_user"]
    assert index_names(ScratchRepo, "probe", ["user_id", "name"]) == ["probe_user_name"]
    assert index_names(ScratchRepo, "probe", ["name", "user_id"]) == []
    assert index_names(ScratchRepo, "probe", ["name"]) == ["probe_name_include"]
    assert index_names(ScratchRepo, "probe", ["id"]) == []
    assert index_names(ScratchRepo, "other", ["user_id"]) == ["other_user"]
    assert index_names(ScratchRepo, "missing", ["user_id"]) == []
  end

  test "remove_index_by_columns is Rails' remove_index by columns: if_exists, one drop, or index_name_for_remove's errors" do
    scratch_sql!("""
    CREATE TABLE probe (id bigserial primary key, user_id bigint, name text);
    CREATE INDEX probe_user ON probe (user_id);
    CREATE INDEX probe_user_name ON probe (user_id, name);
    CREATE INDEX probe_user_name_b ON probe (user_id, name);
    CREATE INDEX probe_id_a ON probe (id);
    CREATE INDEX probe_id_b ON probe (id);
    CREATE INDEX "probe ""quoted\""" ON probe (name);
    """)

    assert_raise ArgumentError,
                 "Multiple indexes found on probe columns [:user_id, :name]. Specify an index name from probe_user_name, probe_user_name_b",
                 fn -> remove_index_by_columns(ScratchRepo, "probe", ["user_id", "name"], []) end

    assert_raise ArgumentError,
                 "Multiple indexes found on probe columns [:id]. Specify an index name from probe_id_a, probe_id_b",
                 fn ->
                   remove_index_by_columns(ScratchRepo, "probe", ["id"],
                     algorithm: :concurrently,
                     if_exists: true
                   )
                 end

    assert index_names(ScratchRepo, "probe", ["id"]) == ["probe_id_a", "probe_id_b"]

    assert {:ok, :ok} =
             ScratchRepo.transaction(fn ->
               remove_index_by_columns(ScratchRepo, "probe", ["user_id"], if_exists: true)
             end)

    refute index_name?(ScratchRepo, "probe", "probe_user")
    assert remove_index_by_columns(ScratchRepo, "probe", ["user_id"], if_exists: true) == :ok

    assert_raise ArgumentError, "No indexes found on probe with the options provided.", fn ->
      remove_index_by_columns(ScratchRepo, "probe", ["user_id"], algorithm: :concurrently)
    end

    assert_raise Postgrex.Error, ~r/cannot run inside a transaction block/, fn ->
      ScratchRepo.transaction(fn ->
        remove_index_by_columns(ScratchRepo, "probe", ["name"], algorithm: :concurrently)
      end)
    end

    assert remove_index_by_columns(ScratchRepo, "probe", ["name"], algorithm: :concurrently) ==
             :ok

    refute index_name?(ScratchRepo, "probe", ~s(probe "quoted"))
  end

  test "foreign_key_name is Rails' foreign_key_for: the first foreign key by name from the table to the table on exactly that column" do
    scratch_sql!("""
    CREATE TABLE probe_parent (id bigserial primary key, code text, UNIQUE (id, code));
    CREATE TABLE probe_other (id bigserial primary key);
    CREATE TABLE probe (id bigserial primary key, parent_id bigint, other_id bigint, code text);
    CREATE TABLE sibling (parent_id bigint);
    ALTER TABLE probe ADD CONSTRAINT probe_fk_b FOREIGN KEY (parent_id) REFERENCES probe_parent (id);
    ALTER TABLE probe ADD CONSTRAINT probe_fk_a FOREIGN KEY (parent_id) REFERENCES probe_parent (id) NOT VALID;
    ALTER TABLE probe ADD CONSTRAINT probe_fk_0 FOREIGN KEY (parent_id, code) REFERENCES probe_parent (id, code);
    ALTER TABLE probe ADD CONSTRAINT probe_fk_other FOREIGN KEY (other_id) REFERENCES probe_other (id);
    ALTER TABLE sibling ADD CONSTRAINT a_sibling_fk FOREIGN KEY (parent_id) REFERENCES probe_parent (id);
    """)

    assert foreign_key_name(ScratchRepo, "probe", "probe_parent", "parent_id") == "probe_fk_a"
    assert foreign_key_name(ScratchRepo, "probe", "probe_other", "other_id") == "probe_fk_other"
    assert foreign_key_name(ScratchRepo, "probe", "probe_other", "parent_id") == nil
    assert foreign_key_name(ScratchRepo, "probe", "probe_parent", "code") == nil
    assert foreign_key_name(ScratchRepo, "sibling", "probe_parent", "parent_id") == "a_sibling_fk"
    assert foreign_key_name(ScratchRepo, "missing", "probe_parent", "parent_id") == nil

    scratch_sql!("ALTER TABLE probe DROP CONSTRAINT probe_fk_a, DROP CONSTRAINT probe_fk_b;")
    assert foreign_key_name(ScratchRepo, "probe", "probe_parent", "parent_id") == nil
  end

  test "quote_ident quotes an identifier as Rails' quote_column_name does, doubling embedded quotes" do
    assert quote_ident("points") == ~s("points")
    assert quote_ident(~s(a"b)) == ~s("a""b")
    assert quote_ident(~s("")) == ~s("""""")

    scratch_sql!("CREATE TABLE #{quote_ident(~s(o"k "x))} (id int);")
    assert table?(ScratchRepo, ~s(o"k "x))
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

  test "with_lock_retry! returns :ok once acquired and raises the last lock error after its attempts" do
    sql!(ScratchRepo, "CREATE TABLE probe (id int)")

    assert with_lock_retry!(
             ScratchRepo,
             fn -> sql!(ScratchRepo, "ALTER TABLE probe ADD COLUMN x int") end,
             lock_timeout: "1s",
             attempts: 1,
             backoff_seconds: 0
           ) == :ok

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

    error =
      assert_raise Postgrex.Error, fn ->
        with_lock_retry!(
          ScratchRepo,
          fn -> sql!(ScratchRepo, "ALTER TABLE probe ADD COLUMN y int") end,
          lock_timeout: "50ms",
          attempts: 2,
          backoff_seconds: 0
        )
      end

    assert error.postgres.code == :lock_not_available
    send(holder.pid, :release)
    Task.await(holder)
    assert column?(ScratchRepo, "probe", "x")
    refute column?(ScratchRepo, "probe", "y")
  end

  test "select_value is Rails' select_value: the first column of the first row, or nil" do
    assert select_value(ScratchRepo, "SELECT * FROM (VALUES (1, 2), (3, 4)) v ORDER BY 1") == 1
    assert select_value(ScratchRepo, "SELECT 1 WHERE false") == nil
    assert select_value(ScratchRepo, "SELECT NULL::boolean") == nil
    assert select_value(ScratchRepo, "SELECT false") == false
    assert select_value(ScratchRepo, "SELECT $1::text || 'b'", ["a"]) == "ab"
  end

  test "repeat_until_zero reruns a batch until it affects no row, each batch committed on its own" do
    scratch_sql!("""
    CREATE TABLE probe (id int);
    INSERT INTO probe SELECT generate_series(1, 5);
    CREATE TABLE seen (id int, xid bigint);
    """)

    assert repeat_until_zero(
             ScratchRepo,
             """
             WITH gone AS (
               DELETE FROM probe WHERE id IN (SELECT id FROM probe ORDER BY id LIMIT $1) RETURNING id
             )
             INSERT INTO seen SELECT id, txid_current() FROM gone
             """,
             [2]
           ) == :ok

    assert select_value(ScratchRepo, "SELECT count(*) FROM probe") == 0
    assert select_value(ScratchRepo, "SELECT count(*) FROM seen") == 5
    assert select_value(ScratchRepo, "SELECT count(DISTINCT xid) FROM seen") == 3
  end

  test "remove_index_concurrently_if_exists drops a named index of the table only when index? sees it" do
    scratch_sql!("""
    CREATE TABLE probe (id bigserial primary key, user_id bigint);
    CREATE TABLE other (id bigint);
    CREATE INDEX probe_user_id ON probe (user_id);
    CREATE INDEX "probe ""quoted\""" ON probe (id, user_id);
    """)

    assert remove_index_concurrently_if_exists(ScratchRepo, "other", "probe_user_id") == nil
    assert remove_index_concurrently_if_exists(ScratchRepo, "probe", "probe_pkey") == nil
    assert index_name?(ScratchRepo, "probe", "probe_user_id")
    assert index_name?(ScratchRepo, "probe", "probe_pkey")
    assert remove_index_concurrently_if_exists(ScratchRepo, "probe", "probe_user_id") == :ok
    refute index_name?(ScratchRepo, "probe", "probe_user_id")
    assert remove_index_concurrently_if_exists(ScratchRepo, "probe", "probe_user_id") == nil
    assert remove_index_concurrently_if_exists(ScratchRepo, "probe", ~s(probe "quoted")) == :ok
    refute index_name?(ScratchRepo, "probe", ~s(probe "quoted"))
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

  test "self_hosted? parses SELF_HOSTED like config/initializers/01_constants.rb:5, stripping as Ruby 3.4's String#strip" do
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
          {"no", false},
          {"", false},
          {"\t\n\v\f\r true \t\n\v\f\r", true},
          {"true\u00A0", false},
          {"\u00A0true", false},
          {"true\u0085", false},
          {"\u3000on", false},
          {"t\u2028", false}
        ] do
      if value, do: System.put_env("SELF_HOSTED", value), else: System.delete_env("SELF_HOSTED")
      assert self_hosted?() == expected, inspect(value)
    end
  end

  test "backfill_allowed? is add_point_dimension_columns_job.rb:28-32: self-hosted and SKIP_POINT_DIMENSION_BACKFILL blank?" do
    saved = Map.new(~w[SELF_HOSTED SKIP_POINT_DIMENSION_BACKFILL], &{&1, System.get_env(&1)})

    on_exit(fn ->
      Enum.each(saved, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)
    end)

    for {self_hosted, skip, expected} <- [
          {nil, nil, true},
          {"false", nil, false},
          {"false", "", false},
          {nil, "", true},
          {nil, " \t\n\v\f\r", true},
          {nil, "\u00A0\u3000\u2028\u0085", true},
          {nil, "\u180E", false},
          {nil, "\u200B", false},
          {nil, "1", false},
          {nil, "false", false},
          {nil, "0", false},
          {"true", nil, true},
          {"true\u00A0", nil, false},
          {"\u3000true", "", false},
          {"\vtrue\r", " ", true},
          {"true\u00A0", "\u00A0", false}
        ] do
      for {name, value} <- [{"SELF_HOSTED", self_hosted}, {"SKIP_POINT_DIMENSION_BACKFILL", skip}],
          do: if(value, do: System.put_env(name, value), else: System.delete_env(name))

      assert backfill_allowed?() == expected, inspect({self_hosted, skip})
    end
  end

  test "env_present? is Ruby's ENV[name].present?: set and not only whitespace" do
    name = "DAWARICH_RELEASE_MIGRATION_ENV_PROBE"
    on_exit(fn -> System.delete_env(name) end)

    for {value, expected} <- [
          {nil, false},
          {"", false},
          {" \t\n\v\f\r", false},
          {" \u3000 \u0085", false},
          {"\u00A0\u2028\u202F\u205F\u1680", false},
          {"\u180E", true},
          {"\u200B", true},
          {"1", true},
          {"false", true},
          {" x ", true}
        ] do
      if value, do: System.put_env(name, value), else: System.delete_env(name)
      assert env_present?(name) == expected, inspect(value)
    end
  end
end
