defmodule Dawarich.ReleaseOperations.DropLegacyCoordinatesTest do
  use Dawarich.ScratchCase

  import ExUnit.CaptureLog

  alias Dawarich.ReleaseMigration
  alias Dawarich.ReleaseOperations.DropLegacyCoordinates

  setup do
    scratch_sql!("CREATE TABLE points (id bigserial PRIMARY KEY)")

    on_exit(fn ->
      scratch_sql!("DROP EVENT TRIGGER IF EXISTS a12h_observe_drop")
      scratch_sql!("DROP EVENT TRIGGER IF EXISTS a12h_reject_drop")
    end)

    :ok
  end

  test "drops either legacy coordinate column with transaction-local timeouts" do
    scratch_sql!("CREATE TABLE ddl_timeouts (statement_timeout text, lock_timeout text)")

    scratch_sql!("""
    CREATE FUNCTION observe_drop() RETURNS event_trigger LANGUAGE plpgsql AS $$
    BEGIN
      INSERT INTO ddl_timeouts VALUES (current_setting('statement_timeout'), current_setting('lock_timeout'));
    END
    $$
    """)

    scratch_sql!("""
    CREATE EVENT TRIGGER a12h_observe_drop ON ddl_command_end
    WHEN TAG IN ('ALTER TABLE') EXECUTE FUNCTION observe_drop()
    """)

    previous = timeouts()
    changeset = DropLegacyCoordinates.new(%{"version" => 1})
    assert changeset.valid?
    assert Ecto.Changeset.get_field(changeset, :max_attempts) == 288
    assert DropLegacyCoordinates.backoff(%Oban.Job{attempt: 2}) == 300

    for columns <- [~w(latitude longitude), ~w(latitude), ~w(longitude), []] do
      for column <- columns, do: scratch_sql!("ALTER TABLE points ADD COLUMN #{column} numeric")
      scratch_sql!("DELETE FROM ddl_timeouts")
      assert DropLegacyCoordinates.run(ScratchRepo) == :ok
      refute ReleaseMigration.column?(ScratchRepo, "points", "latitude")
      refute ReleaseMigration.column?(ScratchRepo, "points", "longitude")
      assert timeouts() == previous

      expected = if columns == [], do: [], else: [["0", "5s"]]
      assert ScratchRepo.query!("SELECT * FROM ddl_timeouts", [], log: false).rows == expected
    end

    assert DropLegacyCoordinates.perform(%Oban.Job{args: %{"version" => 2}}) ==
             {:cancel, :unsupported_version}
  end

  test "failed drop leaves columns intact and reports final exhaustion" do
    scratch_sql!("ALTER TABLE points ADD COLUMN latitude numeric, ADD COLUMN longitude numeric")

    for {state, code} <- [{"55P03", :lock_not_available}, {"57014", :query_canceled}] do
      scratch_sql!("""
      CREATE OR REPLACE FUNCTION reject_drop() RETURNS event_trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF current_query() LIKE '%DROP COLUMN%' THEN
          RAISE EXCEPTION USING ERRCODE = '#{state}', MESSAGE = 'A12h forced DDL failure';
        END IF;
      END
      $$
      """)

      scratch_sql!("""
      CREATE EVENT TRIGGER a12h_reject_drop ON ddl_command_start
      WHEN TAG IN ('ALTER TABLE') EXECUTE FUNCTION reject_drop()
      """)

      for attempt <- [1, 288] do
        log =
          capture_log(fn ->
            error =
              assert_raise Postgrex.Error, fn ->
                DropLegacyCoordinates.run(ScratchRepo, %Oban.Job{
                  attempt: attempt,
                  max_attempts: 288
                })
              end

            assert error.postgres.code == code
          end)

        assert ReleaseMigration.column?(ScratchRepo, "points", "latitude")
        assert ReleaseMigration.column?(ScratchRepo, "points", "longitude")

        if attempt == 288 do
          assert log =~ "gave up after 288 attempts"
          assert log =~ "SET LOCAL lock_timeout = '5s'"
          assert log =~ "DROP COLUMN IF EXISTS latitude, DROP COLUMN IF EXISTS longitude"
        else
          refute log =~ "gave up"
        end
      end

      scratch_sql!("DROP EVENT TRIGGER a12h_reject_drop")
    end
  end

  defp timeouts do
    ScratchRepo.query!(
      "SELECT current_setting('statement_timeout'), current_setting('lock_timeout')",
      [],
      log: false
    ).rows
  end
end
