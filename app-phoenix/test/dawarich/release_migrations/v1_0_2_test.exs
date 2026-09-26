defmodule Dawarich.ReleaseMigrations.V1_0_2Test do
  use Dawarich.ScratchCase

  alias Dawarich.ReleaseMigrations.V1_0_2

  @users ~s|INSERT INTO users (deleted_at) VALUES (NULL), ('2026-01-01'), (NULL)|
  @imports ~s|INSERT INTO imports (source) VALUES ('owntracks'), ('gpx'), ('geojson')|

  test "20260125100000 without users.deleted_at rescues the import count" do
    scratch_sql!("CREATE TABLE users (id bigserial PRIMARY KEY)")
    scratch_sql!("INSERT INTO users DEFAULT VALUES")
    scratch_sql!("CREATE TABLE imports (id bigserial PRIMARY KEY, source character varying)")
    scratch_sql!(@imports)

    assert step().(ScratchRepo) == {:jobs, []}
  end

  test "20260125100000 enqueues no user job, as Rails' missing TransportationModes::BackfillJob raises into the rescue, and rescues the integer imports.source select" do
    scratch_sql!("CREATE TABLE users (id bigserial PRIMARY KEY, deleted_at timestamp)")
    scratch_sql!(@users)
    scratch_sql!("CREATE TABLE imports (id bigserial PRIMARY KEY, source integer)")
    scratch_sql!("INSERT INTO imports (source) VALUES (0), (1)")

    assert step().(ScratchRepo) == {:jobs, []}
  end

  test "20260125100000 staggers the import jobs 10 s apart after every counted user" do
    scratch_sql!("CREATE TABLE users (id bigserial PRIMARY KEY, deleted_at timestamp)")
    scratch_sql!(@users)
    scratch_sql!("CREATE TABLE imports (id bigserial PRIMARY KEY, source character varying)")
    scratch_sql!(@imports)

    assert step().(ScratchRepo) ==
             {:jobs,
              [
                {"TransportationModes::ImportBackfillJob", [1], 180},
                {"TransportationModes::ImportBackfillJob", [3], 190}
              ]}
  end

  defp step do
    {_, step, _} = List.keyfind(V1_0_2.steps(), "20260125100000", 0)
    step
  end
end
