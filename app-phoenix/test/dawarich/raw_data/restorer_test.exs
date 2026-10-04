defmodule Dawarich.RawData.RestorerTest do
  use Dawarich.JobsCase

  alias Dawarich.{ScratchRepo, Wave6Archives, Wave6Fixtures}
  alias Dawarich.RawData.{Archiver, Restorer}

  setup do
    Wave6Fixtures.reset!()

    %{
      storage: Wave6Fixtures.local_storage!(),
      key: Wave6Archives.key(),
      user: Wave6Fixtures.user!()
    }
  end

  defp point!(user, n),
    do:
      Wave6Fixtures.point!(user, %{
        "raw_data" => Jason.Fragment.new(~s({"acc":0.30000000000000004,"n":#{n}}))
      })

  test "restores the points still linked to each archive of the month and counts the rest", ctx do
    [p1, p2, p3] = for n <- 1..3, do: point!(ctx.user, n)
    {:continue, _} = Archiver.pass(ScratchRepo, ctx.storage, ctx.key, ctx.user, 0, chunk_size: 3)
    p4 = point!(ctx.user, 4)
    {:continue, _} = Archiver.pass(ScratchRepo, ctx.storage, ctx.key, ctx.user, p3)
    [[second]] = rows("SELECT raw_data_archive_id FROM points WHERE id = $1", [p4])
    ScratchRepo.query!("UPDATE points SET raw_data_archive_id = $1 WHERE id = $2", [second, p1])
    ScratchRepo.query!("UPDATE points SET raw_data = '{}'::jsonb")
    ScratchRepo.query!("DELETE FROM points WHERE id = $1", [p2])

    assert Restorer.restore_month(ScratchRepo, ctx.storage, ctx.key, ctx.user, 2020, 1) ==
             %{restored: 2, missing: 1, skipped: 1}

    assert rows(
             "SELECT id, raw_data::text, raw_data_archived, raw_data_archive_id IS NULL FROM points ORDER BY id"
           ) == [
             [p1, "{}", true, false],
             [p3, ~s({"n": 3, "acc": 0.3}), false, true],
             [p4, ~s({"n": 4, "acc": 0.3}), false, true]
           ]
  end

  test "raises Rails' message when the month has no archive", ctx do
    assert_raise RuntimeError, "No archives found for user #{ctx.user}, 2020-1", fn ->
      Restorer.restore_month(ScratchRepo, ctx.storage, ctx.key, ctx.user, 2020, 1)
    end
  end
end
