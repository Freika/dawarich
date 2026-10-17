defmodule Dawarich.FixtureStorageTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db

  test "reset deletes committed fixtures without replacing storage" do
    rows(
      "INSERT INTO users(id,email,created_at,updated_at) VALUES(987001,'storage@example.test',now(),now())"
    )

    rows(
      "INSERT INTO points(user_id,timestamp,lonlat,created_at,updated_at) VALUES(987001,1,ST_SetSRID(ST_MakePoint(12,51),4326),now(),now())"
    )

    rows("INSERT INTO phoenix.leases(name,holder,expires_at) VALUES('storage','test',now())")
    before = storage()

    for _ <- 1..2 do
      :ok = Dawarich.JobsCase.reset!(ScratchRepo)
      assert rows("SELECT count(*) FROM users") == [[0]]
      assert rows("SELECT count(*) FROM points") == [[0]]
      assert rows("SELECT count(*) FROM phoenix.leases") == [[0]]
      assert Task.async(fn -> rows("SELECT count(*) FROM users") end) |> Task.await() == [[0]]
      assert storage() == before
    end
  end

  defp storage do
    rows("SELECT oid,relfilenode FROM pg_class WHERE relfilenode > 0 ORDER BY oid")
  end
end
