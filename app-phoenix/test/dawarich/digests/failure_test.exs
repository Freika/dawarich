defmodule Dawarich.Digests.FailureTest do
  use Dawarich.JobsCase

  alias Dawarich.DigestFixtures
  alias Dawarich.Digests.Failure

  test "digest failure notification matches saved locale message and twenty-line stack" do
    corpus =
      __DIR__
      |> Path.join("../../fixtures/a12d1b2/jobs.json")
      |> File.read!()
      |> Jason.decode!()

    for kind <- ~w(monthly yearly), locale <- ~w(en fr) do
      kase = Enum.find(corpus["workers"], &(&1["id"] == "digest_raise_#{kind}_#{locale}"))
      reset!(ScratchRepo)
      DigestFixtures.row!(ScratchRepo, "users", hd(kase["input"]["users"]))
      error = %RuntimeError{message: "synthetic digest failure"}
      stack = Enum.map(1..25, &"synthetic frame #{&1}")
      id = Failure.create!(ScratchRepo, kind, 14101, error, stack)

      [[code, title, content]] =
        rows("SELECT kind,title,content FROM notifications WHERE id=$1", [id])

      assert code == 2
      assert ["error", title, content] == hd(kase["expected"]["notifications"])
      assert [[^id]] = rows("SELECT notification_id FROM phoenix.notification_events")

      for empty <- [nil, []] do
        empty_id = Failure.create!(ScratchRepo, kind, 14101, error, empty)
        [[empty_content]] = rows("SELECT content FROM notifications WHERE id=$1", [empty_id])
        assert empty_content == String.replace(content, Enum.join(Enum.take(stack, 20), "\n"), "")
      end

      zero_id = Failure.create!(ScratchRepo, kind, 14101, %RuntimeError{message: "0"}, [])
      [[zero_content]] = rows("SELECT content FROM notifications WHERE id=$1", [zero_id])

      assert zero_content ==
               content
               |> String.replace("synthetic digest failure", "0")
               |> String.replace(Enum.join(Enum.take(stack, 20), "\n"), "")

      rows("UPDATE users SET deleted_at=now() WHERE id=14101")
      assert Failure.create!(ScratchRepo, kind, 14101, error, stack) == :missing
      assert Failure.create!(ScratchRepo, kind, 0, error, stack) == :missing
      assert [[4]] = rows("SELECT count(*) FROM notifications")
      assert [[4]] = rows("SELECT count(*) FROM phoenix.notification_events")
    end
  end
end
