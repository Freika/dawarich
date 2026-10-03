defmodule Dawarich.Achievements.CelebrationsTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.Achievements.Celebrations
  @stamp "2026-07-19T12:00:00+02:00"

  setup do
    rows(
      "INSERT INTO users(id,email,created_at,updated_at) VALUES(901,'celebrate@example.test',now(),now()),(902,'other@example.test',now(),now())"
    )

    :ok
  end

  defp exploration(user, state) do
    rows(
      "INSERT INTO achievement_progresses(user_id,achievement_key,state,created_at,updated_at) VALUES($1,'exploration',$2,now(),now())",
      [user, state]
    )
  end

  test "GET records no empty exploration or unrelated carrier" do
    exploration(902, %{"earned" => %{"DE" => "date"}})
    assert :ok = Celebrations.record_seen!(ScratchRepo, 901, ["country_de"], @stamp)
    assert [[0]] = rows("SELECT count(*) FROM achievement_progresses WHERE user_id=901")

    assert [[%{"earned" => %{"DE" => "date"}}]] =
             rows("SELECT state FROM achievement_progresses WHERE user_id=902")
  end

  test "records exact local ISO timestamp and preserves other state" do
    exploration(901, %{
      "earned" => %{"DE" => "date"},
      "celebrated" => %{"continent_asia" => "old"},
      "other" => [1]
    })

    assert :ok = Celebrations.record_seen!(ScratchRepo, 901, ["country_de"], @stamp)

    assert [
             [
               %{
                 "earned" => %{"DE" => "date"},
                 "celebrated" => %{"continent_asia" => "old", "country_de" => @stamp},
                 "other" => [1]
               }
             ]
           ] = rows("SELECT state FROM achievement_progresses WHERE user_id=901")
  end

  test "real row lock merges latest independently committed earned/celebrated state" do
    exploration(901, %{"earned" => %{"DE" => "before"}})
    parent = self()

    updater =
      Task.async(fn ->
        ScratchRepo.transaction(fn ->
          rows("SELECT id FROM achievement_progresses WHERE user_id=901 FOR UPDATE")
          send(parent, :locked)

          receive do
            :release -> :ok
          end

          rows("UPDATE achievement_progresses SET state=$1 WHERE user_id=901", [
            %{
              "earned" => %{"DE" => "after", "FR" => "new"},
              "celebrated" => %{"continent_asia" => "other-client"}
            }
          ])
        end)
      end)

    assert_receive :locked

    viewer =
      Task.async(fn -> Celebrations.record_seen!(ScratchRepo, 901, ["country_de"], @stamp) end)

    assert nil == Task.yield(viewer, 100)
    send(updater.pid, :release)
    Task.await(updater)
    assert :ok = Task.await(viewer)

    assert [
             [
               %{
                 "earned" => %{"DE" => "after", "FR" => "new"},
                 "celebrated" => %{"continent_asia" => "other-client", "country_de" => @stamp}
               }
             ]
           ] = rows("SELECT state FROM achievement_progresses WHERE user_id=901")
  end
end
