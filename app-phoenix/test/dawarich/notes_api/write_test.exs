defmodule Dawarich.NotesApi.WriteTest do
  use Dawarich.IngestCase, async: true, group: :notes_fixture_ids

  alias Dawarich.NotesApi.Write

  @now ~U[2026-10-03 12:00:00Z]
  @input %{"body" => "Synthetic created", "noted_at" => "2026-09-02T12:00:00Z"}
  @date_error {:ok, 422, {:object, [{"errors", ["Date has already been taken"]}]}}

  setup do
    owner = user!()
    other = user!()

    for {user, offset} <- [{owner, 0}, {other, 1}] do
      Repo.query!(
        "INSERT INTO trips (id,user_id,name,started_at,ended_at,created_at,updated_at) VALUES ($1,$2,'Synthetic trip','2026-09-01','2026-09-03 23:59:59',NOW(),NOW())",
        [952_101 + offset, user]
      )

      Repo.query!(
        "INSERT INTO areas (id,user_id,name,latitude,longitude,radius,created_at,updated_at) VALUES ($1,$2,'Synthetic area',52,13,100,NOW(),NOW())",
        [952_111 + offset, user]
      )

      Repo.query!(
        "INSERT INTO visits (id,user_id,name,started_at,ended_at,duration,created_at,updated_at) VALUES ($1,$2,'Synthetic visit','2026-09-01','2026-09-01 01:00:00',60,NOW(),NOW())",
        [952_121 + offset, user]
      )

      Repo.query!(
        "INSERT INTO places (id,user_id,name,latitude,longitude,created_at,updated_at) VALUES ($1,$2,'Synthetic place',52,13,NOW(),NOW())",
        [952_131 + offset, user]
      )
    end

    Repo.query!(
      "INSERT INTO notes (id,user_id,title,body,noted_at,lonlat,source_digest,created_at,updated_at) VALUES (952201,$1,'Original title','Original body','2026-09-01 22:30:00',ST_SetSRID(ST_MakePoint(13.405,52.52),4326)::geography,'synthetic-source-digest','2026-09-01 12:00:00','2026-09-01 12:00:00')",
      [owner]
    )

    %{owner: owner, other: other}
  end

  @tag mutation: "M-review-note-dirty"
  test "title PATCH preserves an interleaved body PATCH", %{owner: owner} do
    handler = "a4rest-note-dirty"

    :ok =
      :telemetry.attach(
        handler,
        [:dawarich, :repo, :query],
        &__MODULE__.interleave/4,
        {self(), owner, handler}
      )

    on_exit(fn -> :telemetry.detach(handler) end)
    assert {:ok, 200, _} = Write.update(owner, 952_201, %{"title" => "Edited title"}, "UTC", @now)
    assert_received :body_committed

    assert Repo.query!("SELECT title,body FROM notes WHERE id=952201").rows ==
             [["Edited title", "Concurrent body"]]
  end

  def interleave(_event, _measurements, %{query: query}, {parent, owner, handler}) do
    if self() == parent && String.starts_with?(query, "SELECT title, body, attachable_type") do
      :telemetry.detach(handler)

      assert {:ok, 200, _} =
               Write.update(owner, 952_201, %{"body" => "Concurrent body"}, "UTC", @now)

      send(parent, :body_committed)
    end
  end

  test "body validation accepts 10000 multibyte characters and rejects 10001", %{owner: owner} do
    for body <- [String.duplicate("é", 10_000), String.duplicate("e" <> <<0x301::utf8>>, 5000)] do
      assert {:ok, 201, _} = Write.create(owner, %{@input | "body" => body}, "UTC", @now)

      assert {:ok, 422,
              {:object, [{"errors", ["Body is too long (maximum is 10000 characters)"]}]}} =
               Write.create(owner, %{@input | "body" => body <> "e"}, "UTC", @now)
    end

    assert {:ok, 422, {:object, [{"errors", ["Body can't be blank", "Noted at can't be blank"]}]}} =
             Write.create(owner, %{"body" => " ", "noted_at" => nil}, "UTC", @now)
  end

  test "all allowed attachables require same owner and existing record", %{owner: owner} do
    for {type, id} <- [
          {"Trip", 952_101},
          {"Area", 952_111},
          {"Visit", 952_121},
          {"Place", 952_131}
        ] do
      assert {:ok, 201, _} =
               Write.create(
                 owner,
                 Map.merge(@input, %{"attachable_type" => type, "attachable_id" => id}),
                 "UTC",
                 @now
               )

      assert {:ok, 422, {:object, [{"errors", ["Attachable must belong to the same user"]}]}} =
               Write.create(
                 owner,
                 Map.merge(@input, %{"attachable_type" => type, "attachable_id" => id + 1}),
                 "UTC",
                 @now
               )

      assert {:ok, 422, {:object, [{"errors", ["Attachable can't be blank"]}]}} =
               Write.create(
                 owner,
                 Map.merge(@input, %{"attachable_type" => type, "attachable_id" => 959_999}),
                 "UTC",
                 @now
               )
    end

    assert {:ok, 422, {:object, [{"errors", ["Attachable type is not included in the list"]}]}} =
             Write.create(
               owner,
               Map.merge(@input, %{"attachable_type" => "User", "attachable_id" => owner}),
               "UTC",
               @now
             )
  end

  test "same attachable date rejects duplicates but excludes current note", %{
    owner: owner,
    other: other
  } do
    input = Map.merge(@input, %{"attachable_type" => "Trip", "attachable_id" => 952_101})
    assert {:ok, 201, {:object, fields}} = Write.create(owner, input, "UTC", @now)
    id = Map.new(fields)["id"]
    assert Write.create(owner, input, "UTC", @now) == @date_error
    assert {:ok, 200, _} = Write.update(owner, id, %{"body" => "Edited"}, "UTC", @now)
    Repo.query!("UPDATE notes SET user_id = $1 WHERE id = $2", [other, id])
    assert Write.create(owner, input, "UTC", @now) == @date_error
  end

  test "trip note date respects inclusive trip boundaries", %{owner: owner} do
    for date <- ["2026-08-31", "2026-09-01", "2026-09-03", "2026-09-04"] do
      input =
        Map.merge(@input, %{
          "attachable_type" => "Trip",
          "attachable_id" => 952_101,
          "noted_at" => date <> "T12:00:00Z"
        })

      if date in ["2026-09-01", "2026-09-03"] do
        assert {:ok, 201, _} = Write.create(owner, input, "UTC", @now)
      else
        assert {:ok, 422, {:object, [{"errors", ["Date must be within the trip date range"]}]}} =
                 Write.create(owner, input, "UTC", @now)
      end
    end
  end

  test "single coordinate preserves geometry and zero pair rebuilds it", %{owner: owner} do
    assert {:ok, 200, {:object, fields}} =
             Write.update(owner, 952_201, %{"latitude" => 0}, "UTC", @now)

    assert Map.new(fields)["latitude"] == 52.52
    assert Map.new(fields)["longitude"] == 13.405
    assert Map.new(fields)["updated_at"] == "2026-09-01T12:00:00.000Z"

    assert {:ok, 200, {:object, zero}} =
             Write.update(owner, 952_201, %{"latitude" => 0, "longitude" => 0}, "UTC", @now)

    assert Map.new(zero)["latitude"] == 0.0
    assert Map.new(zero)["longitude"] == 0.0
    assert Map.new(zero)["updated_at"] == "2026-10-03T12:00:00.000Z"

    assert {:ok, 201, {:object, created}} =
             Write.create(owner, Map.merge(@input, %{"latitude" => 0}), "UTC", @now)

    assert Map.new(created)["latitude"] == nil

    assert {:ok, 200, _} =
             Write.update(owner, 952_201, %{"latitude" => nil, "longitude" => nil}, "UTC", @now)

    assert Repo.query!("SELECT ST_X(lonlat::geometry) FROM notes WHERE id = 952201").rows == [
             [0.0]
           ]
  end

  test "update preserves source_digest and destroy returns translated message", %{
    owner: owner,
    other: other
  } do
    Repo.query!(
      "INSERT INTO action_text_rich_texts (id,name,record_type,record_id,body,created_at,updated_at) VALUES (952601,'body','Note',952201,'Synthetic retained text',NOW(),NOW())"
    )

    assert {:replay, _} =
             Write.update(owner, 952_201, %{"body" => %{"bad" => "shape"}}, "UTC", @now)

    assert {:ok, 200, _} =
             Write.update(
               owner,
               952_201,
               %{"body" => "Edited", "source_digest" => "ignored", "user_id" => other},
               "UTC",
               @now
             )

    assert Repo.query!("SELECT source_digest,user_id FROM notes WHERE id = 952201").rows == [
             ["synthetic-source-digest", owner]
           ]

    assert Write.destroy(other, 952_201, "UTC") == :not_found

    assert Write.destroy(owner, 952_201, "UTC") ==
             {:ok, 200, {:object, [{"message", "Note was successfully deleted"}]}}

    assert Repo.query!("SELECT id FROM notes WHERE id = 952201").rows == []

    assert Repo.query!("SELECT body FROM action_text_rich_texts WHERE id = 952601").rows == [
             ["Synthetic retained text"]
           ]

    assert commands() == []
  end
end
