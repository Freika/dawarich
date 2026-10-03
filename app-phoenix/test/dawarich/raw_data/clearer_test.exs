defmodule Dawarich.RawData.ClearerTest do
  use Dawarich.JobsCase

  alias Dawarich.{ScratchRepo, Wave6Archives, Wave6Fixtures}
  alias Dawarich.RawData.Clearer

  setup do
    Wave6Fixtures.reset!()
    user = Wave6Fixtures.user!()

    archive = fn month, verified_days ->
      id = Wave6Archives.archive!(user, %{"month" => month, "chunk_number" => 1})

      ScratchRepo.query!(
        "UPDATE points_raw_data_archives SET verified_at = now() - make_interval(days => $2::integer) WHERE id = $1 AND $2::integer IS NOT NULL",
        [id, verified_days]
      )

      point =
        Wave6Fixtures.point!(user, %{
          "raw_data" => %{"m" => month},
          "raw_data_archived" => true,
          "raw_data_archive_id" => id
        })

      {id, point}
    end

    %{user: user, archive: archive}
  end

  defp raw(point), do: hd(hd(rows("SELECT raw_data::text FROM points WHERE id = $1", [point])))

  test "a cooling period keeps archives verified less than that many days ago", ctx do
    {_, old} = ctx.archive.(1, 10)
    {_, fresh} = ctx.archive.(2, 1)
    assert Clearer.clear_all(ScratchRepo, 7) == 1
    assert {raw(old), raw(fresh)} == {"{}", ~s({"m": 2})}
  end

  test "without a cooling period every verified archive is cleared, unverified ones are not",
       ctx do
    {_, verified} = ctx.archive.(1, 0)
    {_, unverified} = ctx.archive.(2, nil)
    assert Clearer.clear_all(ScratchRepo, nil) == 1
    assert {raw(verified), raw(unverified)} == {"{}", ~s({"m": 2})}
  end

  test "clear_month clears only that month", ctx do
    {_, january} = ctx.archive.(1, 0)
    {_, february} = ctx.archive.(2, 0)
    assert Clearer.clear_month(ScratchRepo, ctx.user, 2020, 2) == 1
    assert {raw(january), raw(february)} == {~s({"m": 1}), "{}"}
  end

  test "a point moved to an unverified archive between reading and clearing keeps its raw_data",
       ctx do
    {_verified, point} = ctx.archive.(1, 0)
    {unverified, _} = ctx.archive.(2, nil)

    move = fn ->
      ScratchRepo.query!("UPDATE points SET raw_data_archive_id = $1 WHERE id = $2", [
        unverified,
        point
      ])
    end

    assert Clearer.clear_all(ScratchRepo, nil, before_clear: move) == 0
    assert raw(point) == ~s({"m": 1})
  end
end
