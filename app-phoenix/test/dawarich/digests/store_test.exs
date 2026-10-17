defmodule Dawarich.Digests.StoreTest do
  use Dawarich.JobsCase, async: false

  alias Dawarich.DigestFixtures
  alias Dawarich.Digests.{CalculateMonth, CalculateYear, Context, Store}

  test "yearly duplicate cleanup keeps the oldest row and its share mail and flight metadata" do
    assert {:error, :recorded} =
             ScratchRepo.transaction(fn ->
               kase = DigestFixtures.case!("duplicates_yearly")
               DigestFixtures.load!(ScratchRepo, kase)
               assert length(DigestFixtures.digests(ScratchRepo, 14101)) == 2
               assert save(kase) == 14601
               assert DigestFixtures.digests(ScratchRepo, 14101) == kase["expected"]["rows"]
               ScratchRepo.rollback(:recorded)
             end)
  end

  test "unchanged attributes leave updated_at untouched and monthly updates preserve metadata" do
    for id <-
          ~w(unchanged_monthly unchanged_yearly existing_monthly existing_yearly berlin_monthly berlin_yearly) do
      assert {:error, :recorded} =
               ScratchRepo.transaction(fn ->
                 kase = DigestFixtures.case!(id)
                 DigestFixtures.load!(ScratchRepo, kase)
                 saved_id = save(kase)
                 if kase["before"] != [], do: assert(saved_id == kase["expected"]["result_id"])
                 expected = Enum.map(kase["expected"]["rows"], &Map.put(&1, "id", saved_id))
                 assert DigestFixtures.digests(ScratchRepo, 14101) == expected
                 ScratchRepo.rollback(:recorded)
               end)
    end
  end

  test "an invalid existing yearly month fails validation and leaves its persisted row unchanged" do
    assert {:error, :recorded} =
             ScratchRepo.transaction(fn ->
               kase = DigestFixtures.case!("invalid_yearly_yearly")
               DigestFixtures.load!(ScratchRepo, kase)
               before = DigestFixtures.digests(ScratchRepo, 14101)

               error =
                 assert_raise Store.Invalid, kase["expected"]["error"]["message"], fn ->
                   save(kase)
                 end

               assert error.details == kase["expected"]["error"]["details"]
               assert DigestFixtures.digests(ScratchRepo, 14101) == before
               ScratchRepo.rollback(:recorded)
             end)
  end

  defp save(kase) do
    context = Context.load!(ScratchRepo, 14101, DigestFixtures.options(kase))
    call = kase["call"]

    attrs =
      if call["kind"] == "monthly",
        do: CalculateMonth.attributes(ScratchRepo, context, call["year"], call["month"]),
        else: CalculateYear.attributes(ScratchRepo, context, call["year"])

    Store.save!(
      ScratchRepo,
      context,
      call["kind"],
      call["year"],
      call["month"],
      attrs,
      DigestFixtures.options(kase)
    )
  end
end
