defmodule Dawarich.Achievements.DeckClaimTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.Achievements.Deck
  alias Dawarich.Test.RailsUser

  @now ~U[2026-10-04 22:30:00.000000Z]
  @old ~N[2026-10-03 22:30:00.000000]

  setup do
    for id <- [44001, 44002],
        do: RailsUser.insert!(%{id: id, email: "deck-#{id}@example.invalid"}, ScratchRepo)

    event!(42001, 44001, "FR")
    event!(42002, 44001, "DE")
    event!(42004, 44002, "ES")
    :ok
  end

  test "claims resumes expires and bounds the Rails deck lease" do
    fixture =
      Path.expand("../../fixtures/achievement_unlocks/lease.json", __DIR__)
      |> File.read!()
      |> Jason.decode!()

    foreign = rows("SELECT to_jsonb(e) FROM achievement_unlock_events e WHERE user_id=44002")
    claim = Deck.claim(ScratchRepo, 44001, %{}, context(0))
    assert claim.event.id == fixture["claim"]["event"]["id"]
    assert claim.remaining == fixture["claim"]["remaining"]
    assert claim.batch_end_id == fixture["claim"]["batch_end_id"]
    token = claim.event.claim_token
    assert token =~ ~r/\A[0-9a-f]{32}\z/
    assert claim.event.created_at == @old
    assert claim.event.updated_at == DateTime.to_naive(@now)
    event!(42003, 44001, "PL")
    assert Deck.claim(ScratchRepo, 44001, %{"batch_end_id" => 42000}, context(0)) == :busy
    assert Deck.claim(ScratchRepo, 44001, %{}, context(45)) == :busy

    resume =
      Deck.claim(
        ScratchRepo,
        44001,
        %{"claim_token" => token, "batch_end_id" => 42002},
        context(45)
      )

    assert resume.event.claim_token == token
    assert resume.event.claimed_at == DateTime.to_naive(DateTime.add(@now, 45))
    assert resume.event.updated_at == resume.event.claimed_at
    assert resume.remaining == fixture["resume"]["remaining"]

    outside =
      Deck.claim(
        ScratchRepo,
        44001,
        %{"claim_token" => token, "batch_end_id" => 42000},
        context(45)
      )

    assert outside.event.id == 42001 and outside.remaining == 0 and outside.batch_end_id == 42000

    expired = Deck.claim(ScratchRepo, 44001, %{"batch_end_id" => 42002}, context(91))
    assert expired.event.id == 42001 and expired.event.claim_token != token
    assert expired.remaining == fixture["expired_46"]["remaining"]
    assert expired.event.created_at == @old

    rows(
      "UPDATE achievement_unlock_events SET seen_at=$1,claimed_at=NULL,claim_token=NULL WHERE id=42001",
      [@old]
    )

    bounded = Deck.claim(ScratchRepo, 44001, %{"batch_end_id" => 42002}, context(91))
    assert bounded.event.id == 42002 and bounded.remaining == 1 and bounded.batch_end_id == 42002

    rows(
      "UPDATE achievement_unlock_events SET seen_at=$1,claimed_at=NULL,claim_token=NULL WHERE id=42002",
      [@old]
    )

    assert Deck.claim(ScratchRepo, 44001, %{"batch_end_id" => 42002}, context(91)) == nil
    assert [[nil]] = rows("SELECT claim_token FROM achievement_unlock_events WHERE id=42003")

    assert rows("SELECT to_jsonb(e) FROM achievement_unlock_events e WHERE user_id=44002") ==
             foreign

    rows("UPDATE achievement_unlock_events SET seen_at=$1 WHERE user_id=44001", [@old])
    assert Deck.claim(ScratchRepo, 44001, %{}, context(91)) == nil
  end

  test "two real contenders reveal one event and use time after lock acquisition" do
    previous = Deck.claim(ScratchRepo, 44001, %{}, context(0))
    clock = :atomics.new(1, [])
    :atomics.put(clock, 1, 45)
    parent = self()

    holder =
      Task.async(fn ->
        ScratchRepo.transaction(fn ->
          rows("SELECT id FROM users WHERE id=44001 FOR UPDATE")
          send(parent, :locked)

          receive do
            :release -> :ok
          end
        end)
      end)

    assert_receive :locked

    hook = fn :before_lock ->
      [[pid]] = rows("SELECT pg_backend_pid()")
      send(parent, {:waiting, pid})
    end

    context = %{clock: fn -> DateTime.add(@now, :atomics.get(clock, 1)) end, hook: hook}

    contenders =
      for _ <- 1..2, do: Task.async(fn -> Deck.claim(ScratchRepo, 44001, %{}, context) end)

    assert_receive {:waiting, first}
    assert_receive {:waiting, second}
    assert first != second
    for task <- contenders, do: assert(Task.yield(task, 0) == nil)
    :atomics.put(clock, 1, 46)
    send(holder.pid, :release)
    assert {:ok, :ok} = Task.await(holder)
    results = Enum.map(contenders, &Task.await/1)
    assert Enum.count(results, &(&1 == :busy)) == 1
    winner = Enum.find(results, &is_map/1)
    assert winner.event.id == previous.event.id
    assert winner.event.claim_token != previous.event.claim_token
    assert winner.event.claimed_at == DateTime.to_naive(DateTime.add(@now, 46))

    assert [[1]] =
             rows(
               "SELECT count(*) FROM achievement_unlock_events WHERE user_id=44001 AND claimed_at IS NOT NULL"
             )
  end

  defp context(seconds), do: %{clock: fn -> DateTime.add(@now, seconds) end}

  defp event!(id, user, key),
    do:
      rows(
        "INSERT INTO achievement_unlock_events(id,user_id,kind,key,created_at,updated_at) VALUES($1,$2,'geography',$3,$4,$4)",
        [id, user, key, @old]
      )
end
