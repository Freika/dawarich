defmodule Dawarich.Digests.CorpusTest do
  use Dawarich.JobsCase, async: false

  alias Dawarich.DigestFixtures

  test "loads every recorded digest input without losing JSON types or other users" do
    cases = DigestFixtures.all()
    assert length(cases) == 66

    for kase <- cases do
      assert {:error, :loaded} =
               ScratchRepo.transaction(fn ->
                 DigestFixtures.load!(ScratchRepo, kase)

                 for {table, rows} <- kase["input"], row <- rows do
                   assert DigestFixtures.project(ScratchRepo, table, row) == row,
                          "#{kase["id"]}: #{table}/#{row["id"]}"
                 end

                 assert [[1]] =
                          ScratchRepo.query!("SELECT count(*) FROM users WHERE id = 14102").rows

                 ScratchRepo.rollback(:loaded)
               end)
    end
  end
end
