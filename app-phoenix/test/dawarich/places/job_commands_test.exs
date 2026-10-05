defmodule Dawarich.Places.JobCommandsTest do
  use Dawarich.JobsCase
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Places.JobCommands
  alias Dawarich.RailsEffects

  test "place effects resolve current leaf owner and keep foreign place untouched" do
    [[user]] =
      rows(
        "INSERT INTO users(email,created_at,updated_at) VALUES('place-effects@example.test',now(),now()) RETURNING id"
      )

    [[other]] =
      rows(
        "INSERT INTO users(email,created_at,updated_at) VALUES('foreign-place-effects@example.test',now(),now()) RETURNING id"
      )

    on_exit(fn -> rows("DELETE FROM places WHERE user_id=ANY($1)", [[user, other]]) end)

    [[place]] =
      rows(
        "INSERT INTO places(user_id,name,source,latitude,longitude,created_at,updated_at) VALUES($1,'Suggested place',1,0,0,now(),now()) RETURNING id",
        [user]
      )

    [[foreign]] =
      rows(
        "INSERT INTO places(user_id,name,source,latitude,longitude,created_at,updated_at) VALUES($1,'Suggested place',1,0,0,now(),now()) RETURNING id",
        [other]
      )

    for type <- ~w(name_fetch delete_if_orphan orphan_cleanup bulk_name_fetch),
        do: Ownership.put!(ScratchRepo, "command:places.#{type}", :oban)

    assert RailsEffects.place_name(ScratchRepo, user, place) == :ok
    assert RailsEffects.place_name(ScratchRepo, user, foreign) == :ok
    assert RailsEffects.orphan_places(ScratchRepo, user, [place, foreign, place]) == :ok
    assert JobCommands.orphan_cleanup(ScratchRepo, user) == :ok
    assert JobCommands.bulk_name_fetch(ScratchRepo) == :ok
    expected = %{"user_id" => user, "place_id" => place}

    assert rows("SELECT command_type,payload FROM job_outbox ORDER BY command_type") == [
             ["places.bulk_name_fetch", %{}],
             ["places.delete_if_orphan", expected],
             ["places.name_fetch", expected],
             ["places.orphan_cleanup", %{"user_id" => user}]
           ]

    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
    assert rows("SELECT name FROM places WHERE id=$1", [foreign]) == [["Suggested place"]]

    for type <- ~w(name_fetch delete_if_orphan orphan_cleanup bulk_name_fetch),
        do: Ownership.put!(ScratchRepo, "command:places.#{type}", :sidekiq)

    assert RailsEffects.place_name(ScratchRepo, user, place) == :ok
    assert RailsEffects.orphan_places(ScratchRepo, user, [place, place]) == :ok
    assert JobCommands.orphan_cleanup(ScratchRepo, user) == :ok
    assert JobCommands.bulk_name_fetch(ScratchRepo) == :ok

    assert rows("SELECT kind,payload FROM phoenix.rails_commands ORDER BY id") == [
             ["place_name_fetch", expected],
             ["places_delete_if_orphan", %{"user_id" => user, "place_ids" => [place]}],
             ["places_orphan_cleanup", %{"user_id" => user}],
             ["places_bulk_name_fetch", %{}]
           ]

    assert_raise Postgrex.Error, fn ->
      ScratchRepo.transaction(fn ->
        Ownership.put!(ScratchRepo, "command:places.name_fetch", :oban)
        RailsEffects.place_name(ScratchRepo, user, place)
        rows("SELECT 1/0")
      end)
    end

    assert rows("SELECT count(*) FROM job_outbox") == [[4]]
  end
end
