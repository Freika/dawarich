defmodule Dawarich.ReleaseMigrations.V1_1_0Test do
  use Dawarich.ScratchCase

  alias Dawarich.ReleaseMigrations.V1_1_0

  test "20260206202634 enqueues nothing when the users select fails, as Rails' rescue does" do
    scratch_sql!("CREATE TABLE users (id bigserial PRIMARY KEY)")
    scratch_sql!("INSERT INTO users DEFAULT VALUES")

    assert step().(ScratchRepo) == {:jobs, []}
  end

  test "20260206202634 staggers one job per kept user, 120 s plus 30 s per earlier user" do
    scratch_sql!("CREATE TABLE users (id bigserial PRIMARY KEY, deleted_at timestamp)")
    scratch_sql!("INSERT INTO users (deleted_at) VALUES (NULL), ('2026-01-01'), (NULL), (NULL)")

    assert step().(ScratchRepo) ==
             {:jobs,
              [
                {"Tracks::DeduplicationJob", [1], 120},
                {"Tracks::DeduplicationJob", [3], 150},
                {"Tracks::DeduplicationJob", [4], 180}
              ]}
  end

  defp step do
    {_, step, _} = List.keyfind(V1_1_0.steps(), "20260206202634", 0)
    step
  end
end
