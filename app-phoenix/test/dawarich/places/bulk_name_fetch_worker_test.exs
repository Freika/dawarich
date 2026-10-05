defmodule Dawarich.Places.BulkNameFetchWorkerTest do
  use Dawarich.JobsCase
  alias Dawarich.Jobs.{Ownership, Processed}
  alias Dawarich.Places.BulkNameFetchWorker, as: Worker
  @oban __MODULE__.Oban

  test "bulk name sweep selects exact default names and publishes each leaf owner once" do
    start_oban(@oban)

    [[user]] =
      rows(
        "INSERT INTO users(email,created_at,updated_at) VALUES('bulk-names@example.test',now(),now()) RETURNING id"
      )

    [[other]] =
      rows(
        "INSERT INTO users(email,created_at,updated_at) VALUES('other-names@example.test',now(),now()) RETURNING id"
      )

    on_exit(fn -> rows("DELETE FROM places WHERE user_id=ANY($1)", [[user, other]]) end)

    [[custom]] =
      rows(
        "INSERT INTO places(user_id,name,latitude,longitude,created_at,updated_at) VALUES($1,'Suggested place ',0,0,now(),now()) RETURNING id",
        [user]
      )

    ids =
      rows(
        "INSERT INTO places(user_id,name,latitude,longitude,created_at,updated_at) SELECT $1,'Suggested place',0,0,now(),now() FROM generate_series(1,1001) RETURNING id",
        [user]
      )
      |> List.flatten()

    [[foreign]] =
      rows(
        "INSERT INTO places(user_id,name,latitude,longitude,created_at,updated_at) VALUES($1,'Suggested place',0,0,now(),now()) RETURNING id",
        [other]
      )

    event = Ecto.UUID.generate()
    args = %{"event_id" => event, "cursor" => 0}
    assert Worker.args_from_command(1, %{}) == {:ok, %{"cursor" => 0}}
    assert Worker.args_from_command(1, %{"user_id" => user}) == {:error, "invalid_payload"}
    assert Worker.args_from_command(2, %{}) == {:error, "unsupported_version"}
    Ownership.put!(ScratchRepo, "command:places.bulk_name_fetch", :oban)
    Ownership.put!(ScratchRepo, "command:places.name_fetch", :oban)

    assert_raise Postgrex.Error, fn ->
      Worker.run(ScratchRepo, @oban, args, hook: fn _ -> rows("SELECT 1/0") end)
    end

    refute Processed.done?(ScratchRepo, Worker.batch_id(args))
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
    assert Worker.run(ScratchRepo, @oban, args) == :ok
    assert Worker.run(ScratchRepo, @oban, args) == :ok

    assert rows(
             "SELECT (args->>'place_id')::bigint FROM oban.oban_jobs WHERE worker='Dawarich.Places.NameFetchWorker' ORDER BY id"
           ) == Enum.map(Enum.take(ids, 1000), &[&1])

    [[next]] =
      rows("SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Places.BulkNameFetchWorker'")

    Ownership.put!(ScratchRepo, "command:places.name_fetch", :sidekiq)
    assert Worker.run(ScratchRepo, @oban, next) == :ok
    assert Worker.run(ScratchRepo, @oban, next) == :ok

    assert rows("SELECT kind,payload FROM phoenix.rails_commands ORDER BY id") == [
             ["place_name_fetch", %{"user_id" => user, "place_id" => List.last(ids)}],
             ["place_name_fetch", %{"user_id" => other, "place_id" => foreign}]
           ]

    assert rows("SELECT name FROM places WHERE id=$1", [custom]) == [["Suggested place "]]
    Ownership.put!(ScratchRepo, "command:places.bulk_name_fetch", :sidekiq)
    released = Map.put(next, "event_id", Ecto.UUID.generate())
    assert Worker.run(ScratchRepo, @oban, released) == :ok
    assert Worker.run(ScratchRepo, @oban, released) == :ok

    assert rows(
             "SELECT kind,payload FROM phoenix.rails_commands WHERE kind='places_bulk_name_fetch'"
           ) == [["places_bulk_name_fetch", %{}]]

    assert Worker.__opts__()[:max_attempts] == 26
  end
end
