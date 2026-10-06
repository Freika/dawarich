defmodule Dawarich.Metrics.ImportsTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.{Wave6Fixtures, EnhancedImport.State}

  setup do
    start_supervised!(Dawarich.Metrics)
    %{user: Wave6Fixtures.user!()}
  end

  defp import!(user) do
    now = NaiveDateTime.utc_now()
    id = Wave6Fixtures.insert!("imports", %{"user_id" => user, "name" => "synthetic.gpx", "source" => 4, "created_at" => now, "updated_at" => now})
    State.load(ScratchRepo, id)
  end

  test "native extraction health exports oldest ages and stalled counts from real states", %{user: user} do
    pending = import!(user)
    running = import!(user)
    missing = import!(user)
    unreadable = import!(user)
    completed = import!(user)
    State.pending!(ScratchRepo, pending)
    State.running!(ScratchRepo, running)
    State.pending!(ScratchRepo, missing)
    State.running!(ScratchRepo, unreadable)
    State.completed!(ScratchRepo, completed, %{})
    stamp = DateTime.utc_now() |> DateTime.add(-21600) |> DateTime.to_iso8601()
    rows("UPDATE imports SET additional_data_extraction=$2 WHERE id=$1", [pending.id, %{"started_at" => stamp}])
    rows("UPDATE imports SET additional_data_extraction='{}' WHERE id=$1", [missing.id])
    rows("UPDATE imports SET additional_data_extraction=$2 WHERE id=$1", [unreadable.id, %{"started_at" => ["invalid", "private"]}])
    rows("UPDATE imports SET additional_data_extraction='{}' WHERE id=$1", [completed.id])
    Dawarich.Metrics.Imports.sample(ScratchRepo)
    body = Dawarich.Metrics.scrape()
    assert body =~ "dawarich_imports_extractions_stalled 3"
    assert Regex.match?(~r/dawarich_imports_extraction_oldest_age_seconds\{state="pending"\} 2160\d/, body)
    assert body =~ ~s(dawarich_imports_extraction_oldest_age_seconds{state="running"})
    refute body =~ "private"
    State.completed!(ScratchRepo, pending, %{})
    State.completed!(ScratchRepo, running, %{})
    State.completed!(ScratchRepo, missing, %{})
    State.completed!(ScratchRepo, unreadable, %{})
    Dawarich.Metrics.Imports.sample(ScratchRepo)
    body = Dawarich.Metrics.scrape()
    assert body =~ "dawarich_imports_extractions_stalled 0"
    assert body =~ ~s(dawarich_imports_extraction_oldest_age_seconds{state="pending"} 0)
    assert body =~ ~s(dawarich_imports_extraction_oldest_age_seconds{state="running"} 0)
    rows("DELETE FROM imports")
    Dawarich.Metrics.Imports.sample(ScratchRepo)
    assert Dawarich.Metrics.scrape() =~ "dawarich_imports_extractions_stalled 0"
  end
end
