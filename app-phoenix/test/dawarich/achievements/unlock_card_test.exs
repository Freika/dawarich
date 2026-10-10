defmodule Dawarich.Achievements.UnlockCardTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.Achievements.{Registry, UnlockCard}
  alias Dawarich.Test.RailsUser

  @square "MULTIPOLYGON (((12.25 51.25,12.25 51.5,12.5 51.5,12.5 51.25,12.25 51.25)))"

  setup do
    Dawarich.Test.AchievementSilhouettes.clear()
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    on_exit(&Dawarich.Test.AchievementSilhouettes.clear/0)
    rows("TRUNCATE countries,regions RESTART IDENTITY")

    for {code, name} <- [{"DE", "Germany"}, {"FR", "France"}] do
      rows(
        "INSERT INTO countries(iso_a2,iso_a3,name,geom,created_at,updated_at) VALUES($1,$1,$2,ST_GeomFromText($3,4326),now(),now())",
        [code, name, @square]
      )
    end

    rows(
      "INSERT INTO regions(code,geom,created_at,updated_at) VALUES('DE-BY',ST_GeomFromText($1,4326),now(),now())",
      [@square]
    )

    :ok
  end

  test "presents set country flat and subdivision unlock cards in owner locale" do
    assert Registry.subdivision_parent("DE-BY").key == "country_de"
    assert Registry.subdivision_parent("missing") == nil

    for row <- corpus() do
      assert present(row) == row["card"], row["name"]
    end

    row = Enum.find(corpus(), &(&1["name"] == "en_subdivision"))

    utc =
      UnlockCard.call(ScratchRepo, event(row), row["state"], %{
        locale: "en",
        settings: %{"timezone" => "UTC"}
      })

    assert utc["attributes"]["earned_label"] == "Unlocked · 4 Oct 2026"
    assert UnlockCard.call(ScratchRepo, %{event(row) | key: "XX"}, %{}, context(row)) == nil

    assert UnlockCard.call(
             ScratchRepo,
             %{event(row) | key: "world_explorer", kind: "set"},
             %{},
             context(row)
           ) == nil
  end

  test "hydrates only the visible card without celebration or award writes" do
    row = Enum.find(corpus(), &(&1["name"] == "en_country_set"))
    RailsUser.insert!(%{id: 42101, email: "unlock-card@example.invalid"}, ScratchRepo)

    rows(
      "INSERT INTO achievement_progresses(user_id,achievement_key,state,created_at,updated_at) VALUES(42101,'exploration',$1,now(),now())",
      [row["state"]]
    )

    rows(
      "INSERT INTO achievement_unlock_events(id,user_id,kind,key,created_at,updated_at) VALUES(42102,42101,'set','country_de',now(),now())"
    )

    before = snapshot()
    owner = self()
    handler = "unlock-card-queries"

    :telemetry.attach(
      handler,
      [:dawarich, :scratch_repo, :query],
      fn _, _, metadata, pid -> send(pid, {:card_query, metadata.query}) end,
      owner
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    assert present(row) == row["card"]
    assert snapshot() == before
    queries = collect_queries([])
    assert Enum.count(queries, &String.contains?(&1, "ST_AsSVG")) == 1

    assert Enum.all?(
             queries,
             &(String.starts_with?(String.trim(&1), "SELECT") or
                 String.starts_with?(String.trim(&1), "WITH"))
           )

    Dawarich.Test.AchievementSilhouettes.clear()
    rows("TRUNCATE countries,regions")
    assert get_in(present(row), ["attributes", "silhouette"]) == nil
    assert snapshot() == before
  end

  defp collect_queries(acc) do
    receive do
      {:card_query, sql} -> collect_queries([sql | acc])
    after
      0 -> acc
    end
  end

  defp snapshot do
    for table <- ~w(achievement_progresses achievement_unlock_events),
        do: rows("SELECT to_jsonb(t) FROM #{table} t ORDER BY id")
  end

  defp corpus,
    do:
      "test/fixtures/achievement_unlocks/cards.json"
      |> File.read!()
      |> Jason.decode!()
      |> Map.fetch!("cards")

  defp event(row) do
    {:ok, at, _} = DateTime.from_iso8601(row["event"]["created_at"])

    %{
      id: row["event"]["id"],
      user_id: row["event"]["user_id"],
      kind: row["event"]["kind"],
      key: row["event"]["key"],
      created_at: DateTime.to_naive(at)
    }
  end

  defp context(row), do: %{locale: row["locale"], settings: %{"timezone" => row["timezone"]}}
  defp present(row), do: UnlockCard.call(ScratchRepo, event(row), row["state"], context(row))
end
