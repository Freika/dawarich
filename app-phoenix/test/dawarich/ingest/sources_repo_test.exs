defmodule Dawarich.Ingest.SourcesRepoTest do
  use Dawarich.IngestCase
  alias Dawarich.Ingest.Sources

  test "a missing dimension column in one actual database cannot disable another repository" do
    assert Dawarich.ScratchRepo.query!(
             "SELECT 1 FROM information_schema.columns WHERE table_schema=current_schema() AND table_name='points' AND column_name='source_id'",
             [],
             log: false
           ).rows == [[1]]

    Repo.query!("ALTER TABLE points DROP COLUMN source_id", [], log: false)
    refute Sources.available?(Repo, 0)
    assert Sources.available?(Dawarich.ScratchRepo, 1)
    refute Sources.available?(Repo, 1)
  end

  test "a present dimension column does not authorize a different database without it" do
    Repo.query!("ALTER TABLE points DROP COLUMN source_id", [], log: false)
    assert Sources.available?(Dawarich.ScratchRepo, 0)
    refute Sources.available?(Repo, 1)
  end
end
