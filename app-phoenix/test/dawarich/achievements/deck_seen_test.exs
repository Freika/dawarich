defmodule Dawarich.Achievements.DeckSeenTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.Achievements.Deck
  alias Dawarich.Test.RailsUser

  @old ~N[2026-10-03 22:30:00.000000]
  @now ~U[2026-10-04 22:31:31.000000Z]

  setup do
    for id <- [44001, 44002],
        do: RailsUser.insert!(%{id: id, email: "seen-#{id}@example.invalid"}, ScratchRepo)

    for {id, owner, key} <- [
          {42001, 44001, "FR"},
          {42002, 44001, "DE"},
          {42003, 44001, "PL"},
          {42004, 44002, "ES"}
        ] do
      rows(
        "INSERT INTO achievement_unlock_events(id,user_id,kind,key,claim_token,claimed_at,created_at,updated_at) VALUES($1,$2,'geography',$3,'synthetic',$4,$4,$4)",
        [id, owner, key, @old]
      )
    end

    :ok
  end

  test "acknowledges only own pending token and repeats own seen acknowledgment" do
    before = row(42001)

    for token <- [nil, "", " \n\t", "wrong"] do
      assert Deck.acknowledge(ScratchRepo, 44001, 42001, token, context()) == false
      assert row(42001) == before
    end

    foreign_before = row(42004)
    foreign_result = Deck.acknowledge(ScratchRepo, 44001, 42004, "synthetic", context())
    assert row(42004) == foreign_before
    assert foreign_result == false
    assert Deck.acknowledge(ScratchRepo, 44001, 99999, "synthetic", context()) == false
    assert Deck.acknowledge(ScratchRepo, 44001, 42001, "synthetic", context()) == true
    assert [[seen, nil, nil, @old, @old]] = row(42001)
    assert seen == DateTime.to_naive(@now)
    snapshot = row(42001)

    assert Deck.acknowledge(ScratchRepo, 44001, 42001, "different", %{
             clock: fn -> DateTime.add(@now, 60) end
           })

    assert row(42001) == snapshot
    assert Deck.acknowledge(ScratchRepo, 44001, 42001, " ", context()) == false
    assert Deck.acknowledge(ScratchRepo, 44002, 42001, "synthetic", context()) == false
  end

  test "dismisses only pending own events through the fixed batch" do
    rows("UPDATE achievement_unlock_events SET seen_at=$1 WHERE id=42001", [@old])
    seen_before = row(42001)
    future_before = row(42003)
    foreign_before = row(42004)

    assert Deck.dismiss_through(ScratchRepo, 44001, 42002, context()) == :ok
    assert row(42003) == future_before
    assert row(42004) == foreign_before
    assert row(42001) == seen_before
    assert [[seen, nil, nil, @old, @old]] = row(42002)
    assert seen == DateTime.to_naive(@now)

    snapshot = rows("SELECT to_jsonb(e) FROM achievement_unlock_events e ORDER BY id")

    for bound <- [nil, 0, -1, "0", "042003", "42003x", 42_003.0, 9_223_372_036_854_775_808] do
      assert Deck.dismiss_through(ScratchRepo, 44001, bound, context()) == :ok
      assert rows("SELECT to_jsonb(e) FROM achievement_unlock_events e ORDER BY id") == snapshot
    end

    assert Deck.dismiss_through(ScratchRepo, 44001, "42002", context()) == :ok
    assert rows("SELECT to_jsonb(e) FROM achievement_unlock_events e ORDER BY id") == snapshot
  end

  defp context, do: %{clock: fn -> @now end}

  defp row(id),
    do:
      rows(
        "SELECT seen_at,claimed_at,claim_token,created_at,updated_at FROM achievement_unlock_events WHERE id=$1",
        [id]
      )
end
