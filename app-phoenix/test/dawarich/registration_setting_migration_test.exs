defmodule Dawarich.RegistrationSettingMigrationTest do
  use Dawarich.ScratchCase

  @version 20_261_004_170_000
  @source Path.expand(
            "../../priv/repo/migrations/20261004170000_allow_nil_registration_setting.exs",
            __DIR__
          )

  setup do
    [{module, _}] = Code.compile_file(@source)
    rows("DELETE FROM phoenix.registration_setting")
    scratch_sql!("ALTER TABLE phoenix.registration_setting ALTER COLUMN enabled SET NOT NULL")
    rows("DELETE FROM phoenix.phoenix_schema_migrations WHERE version=$1", [@version])
    scratch_sql!("CREATE TABLE public.schema_migrations (version text PRIMARY KEY)")
    rows("INSERT INTO public.schema_migrations VALUES ('synthetic-a13g')")

    on_exit(fn ->
      rows("DELETE FROM phoenix.registration_setting")
      rows("DELETE FROM phoenix.phoenix_schema_migrations WHERE version=$1", [@version])
      :ok = up(module)
      Dawarich.MigrationModules.purge()
    end)

    %{module: module}
  end

  test "forward registration migration accepts nil and retains singleton and existing booleans",
       %{module: module} do
    baseline = public_snapshot()
    rows("INSERT INTO phoenix.registration_setting (enabled) VALUES (false)")
    assert up(module) == :ok
    assert rows("SELECT enabled FROM phoenix.registration_setting") == [[false]]
    rows("UPDATE phoenix.registration_setting SET enabled=NULL")
    assert rows("SELECT id, enabled FROM phoenix.registration_setting") == [[true, nil]]

    assert {:error, %{postgres: %{code: :check_violation}}} =
             ScratchRepo.query(
               "INSERT INTO phoenix.registration_setting (id, enabled) VALUES (false, true)",
               [],
               log: false
             )

    assert {:error, %{postgres: %{code: :unique_violation}}} =
             ScratchRepo.query(
               "INSERT INTO phoenix.registration_setting (id, enabled) VALUES (true, true)",
               [],
               log: false
             )

    rows("UPDATE phoenix.registration_setting SET enabled=true")
    assert rows("SELECT enabled FROM phoenix.registration_setting") == [[true]]
    assert public_snapshot() == baseline
  end

  test "down refuses a nil row without losing it", %{module: module} do
    assert up(module) == :ok
    rows("INSERT INTO phoenix.registration_setting (enabled) VALUES (NULL)")
    baseline = public_snapshot()

    assert_raise Postgrex.Error, fn -> down(module) end

    assert rows("SELECT enabled FROM phoenix.registration_setting") == [[nil]]

    assert rows("SELECT version FROM phoenix.phoenix_schema_migrations WHERE version=$1", [
             @version
           ]) ==
             [[@version]]

    rows("DELETE FROM phoenix.registration_setting")
    assert down(module) == :ok

    assert rows(
             "SELECT is_nullable::text FROM information_schema.columns WHERE table_schema='phoenix' AND table_name='registration_setting' AND column_name='enabled'"
           ) == [["NO"]]

    assert up(module) == :ok
    assert public_snapshot() == baseline
  end

  defp up(module),
    do: Ecto.Migrator.up(ScratchRepo, @version, module, prefix: "phoenix", log: false)

  defp down(module),
    do: Ecto.Migrator.down(ScratchRepo, @version, module, prefix: "phoenix", log: false)

  defp public_snapshot do
    {rows(
       "SELECT c.relname, c.relkind::text, a.attname, a.attnotnull FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace LEFT JOIN pg_attribute a ON a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped WHERE n.nspname='public' ORDER BY 1,3"
     ), rows("SELECT version FROM public.schema_migrations ORDER BY version")}
  end

  defp rows(sql, params \\ []), do: ScratchRepo.query!(sql, params, log: false).rows
end
