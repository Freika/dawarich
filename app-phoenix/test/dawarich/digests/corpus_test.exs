defmodule Dawarich.Digests.CorpusTest do
  use Dawarich.JobsCase, async: false

  alias Dawarich.DigestFixtures
  alias Dawarich.Digests.{CalculateMonth, Calculation, Context, Store, Toponyms}

  test "loads every recorded digest input without losing JSON types or other users" do
    cases = DigestFixtures.all()
    assert length(cases) == 67

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

  test "both native calculators match every recorded Rails result and error" do
    on_exit(&cleanup!/0)

    for kase <- DigestFixtures.all() do
      cleanup!()

      assert {:ok, :ok} =
               ScratchRepo.transaction(fn -> DigestFixtures.load!(ScratchRepo, kase) end)

      call = kase["call"]
      opts = DigestFixtures.options(kase)

      result =
        if call["kind"] == "monthly",
          do:
            Calculation.monthly(
              ScratchRepo,
              call["user_id"],
              call["year"],
              call["month"],
              opts
            ),
          else: Calculation.yearly(ScratchRepo, call["user_id"], call["year"], opts)

      expected = kase["expected"]

      if error = expected["error"] do
        assert {:error, actual} = result, kase["id"]

        assert actual.__struct__ == error_module(error["class"], kase["id"]),
               kase["id"]

        assert Exception.message(actual) == error["message"], kase["id"]
        if error["details"], do: assert(actual.details == error["details"], kase["id"])
        assert DigestFixtures.digests(ScratchRepo, 14101) == kase["before"], kase["id"]
      else
        assert {:ok, id} = result, kase["id"]
        assert is_nil(id) == is_nil(expected["result_id"]), kase["id"]
        rows = Enum.map(expected["rows"], &Map.put(&1, "id", id))
        assert DigestFixtures.digests(ScratchRepo, 14101) == rows, kase["id"]
      end
    end
  end

  defp cleanup! do
    reset!(ScratchRepo)

    ScratchRepo.query!(
      "CREATE UNIQUE INDEX IF NOT EXISTS index_digests_on_user_year_period_type_monthless ON public.digests (user_id, year, period_type) WHERE month IS NULL"
    )

    ScratchRepo.query!(
      "ALTER TABLE public.track_segments ALTER COLUMN transportation_mode SET NOT NULL"
    )
  end

  defp error_module("ArgumentError", _), do: ArgumentError
  defp error_module("ActiveRecord::RecordInvalid", _), do: Store.Invalid
  defp error_module("ActiveRecord::RecordNotFound", _), do: Context.UserNotFound
  defp error_module("NoMethodError", "malformed_daily_monthly"), do: CalculateMonth.InvalidDaily
  defp error_module("NoMethodError", _), do: Toponyms.InvalidInteger
end
