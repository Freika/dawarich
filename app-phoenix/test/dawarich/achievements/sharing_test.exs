defmodule Dawarich.Achievements.SharingTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.Achievements.Sharing
  alias Dawarich.Test.RailsUser

  @now ~U[2026-10-04 10:00:00.000000Z]
  @old ~N[2026-10-03 10:00:00.000000]
  @uuid "a10c0000-0000-4000-8000-000000000001"

  setup do
    for id <- [44001, 44002] do
      RailsUser.insert!(%{id: id, email: "sharing-#{id}@example.invalid"}, ScratchRepo)
    end

    :ok
  end

  test "shares the current owner's carrier with Rails boolean and uuid semantics" do
    foreign = carrier!(44002, "country_de", %{"foreign" => true}, true, @uuid <> "-foreign")
    own = carrier!(44001, "country_de", %{"earned" => %{"DE" => "2026-07-19"}}, true, nil)
    foreign_before = row(foreign)

    assert {:ok, %{enabled: false, uuid: uuid}} =
             Sharing.call(ScratchRepo, 44001, "country_de", %{"enabled" => false}, context())

    assert row(foreign) == foreign_before
    assert uuid =~ ~r/\A[0-9a-f-]{36}\z/ and uuid != @uuid
    assert [[%{"earned" => %{"DE" => "2026-07-19"}}, false, ^uuid, @old, updated]] = row(own)
    assert updated == DateTime.to_naive(@now)

    fixtures =
      Path.expand("../../fixtures/achievement_actions/responses.json", __DIR__)
      |> File.read!()
      |> Jason.decode!()

    for fixture <-
          Enum.filter(
            fixtures,
            &(&1["status"] == 200 and is_binary(get_in(&1, ["before", "key"])))
          ) do
      before = fixture["before"]
      key = before["key"]
      rows("DELETE FROM achievement_progresses WHERE user_id=44001")

      id =
        carrier!(44001, key, before["state"], before["enabled"], before["uuid"])

      assert {:ok, result} = Sharing.call(ScratchRepo, 44001, key, fixture["params"], context())
      assert result.enabled == fixture["after"]["enabled"], fixture["name"]
      assert result.uuid == (before["uuid"] || result.uuid)
      assert [[state, _, _, @old, _]] = row(id)
      assert state == before["state"]
      assert row(foreign) == foreign_before
    end

    rows("DELETE FROM achievement_progresses WHERE user_id=44001")
    id = carrier!(44001, "country_de", ["opaque", "source-state"], true, @uuid <> "2")

    assert {:ok, %{enabled: true}} =
             Sharing.call(ScratchRepo, 44001, "country_de", %{"enabled" => true}, context())

    assert [[[_ | _], true, _, @old, @old]] = row(id)

    before = rows("SELECT to_jsonb(p) FROM achievement_progresses p ORDER BY id")

    for input <- [%{"enabled" => nil}, %{"enabled" => ""}, %{"enabled" => %{}}] do
      assert {:unsupported, :input} =
               Sharing.call(ScratchRepo, 44001, "country_fr", input, context())
    end

    assert {:error, :not_found} = Sharing.call(ScratchRepo, 44001, "unknown_key", %{}, context())
    rows("UPDATE users SET deleted_at=$1 WHERE id=44001", [@old])
    assert {:unsupported, :actor} = Sharing.call(ScratchRepo, 44001, "country_fr", %{}, context())
    assert rows("SELECT to_jsonb(p) FROM achievement_progresses p ORDER BY id") == before
  end

  test "concurrent creation and toggles preserve one carrier and source state" do
    {created, pids} = contenders(:before_insert, %{"enabled" => true})
    assert length(Enum.uniq(pids)) == 2
    assert [{:ok, first}, {:ok, second}] = created
    assert first == second and first.enabled
    assert [[1]] = rows("SELECT count(*) FROM achievement_progresses WHERE user_id=44001")

    rows("UPDATE achievement_progresses SET state=$1,sharing_enabled=false WHERE user_id=44001", [
      %{"other-client" => [1], "earned" => %{"DE" => "2026-07-19"}}
    ])

    assert [{:ok, one}, {:ok, two}] = elem(contenders(:before_lock, %{}), 0)
    assert Enum.sort([one.enabled, two.enabled]) == [false, true]
    assert one.uuid == first.uuid and two.uuid == first.uuid

    assert [[state, false, uuid]] =
             rows(
               "SELECT state,sharing_enabled,sharing_uuid FROM achievement_progresses WHERE user_id=44001"
             )

    assert state == %{"other-client" => [1], "earned" => %{"DE" => "2026-07-19"}}
    assert uuid == first.uuid
  end

  defp contenders(stage, input) do
    parent = self()

    hook = fn current ->
      if current == stage do
        [[pid]] = rows("SELECT pg_backend_pid()")
        send(parent, {:ready, self(), pid})

        receive do
          :release -> :ok
        end
      end
    end

    tasks =
      for _ <- 1..2 do
        Task.async(fn ->
          Sharing.call(ScratchRepo, 44001, "country_de", input, Map.put(context(), :hook, hook))
        end)
      end

    assert_receive {:ready, first, first_pid}
    assert_receive {:ready, second, second_pid}
    send(first, :release)
    send(second, :release)
    {Enum.map(tasks, &Task.await/1), [first_pid, second_pid]}
  end

  defp context, do: %{clock: fn -> @now end}

  defp carrier!(user, key, state, enabled, uuid) do
    [[id]] =
      rows(
        "INSERT INTO achievement_progresses(user_id,achievement_key,state,sharing_enabled,sharing_uuid,created_at,updated_at) VALUES($1,$2,$3,$4,$5,$6,$6) RETURNING id",
        [user, key, state, enabled, uuid, @old]
      )

    id
  end

  defp row(id),
    do:
      rows(
        "SELECT state,sharing_enabled,sharing_uuid,created_at,updated_at FROM achievement_progresses WHERE id=$1",
        [id]
      )
end
