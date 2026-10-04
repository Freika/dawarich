defmodule Dawarich.Digests.CalculationTest do
  use Dawarich.JobsCase, async: false

  alias Dawarich.DigestFixtures
  alias Dawarich.Digests.{Calculation, Store}

  test "monthly and yearly public calls persist exact recorded attributes with no outbox or mail" do
    for name <- ~w(berlin_monthly berlin_yearly invalid_yearly_yearly) do
      kase = DigestFixtures.case!(name)
      reset!(ScratchRepo)
      DigestFixtures.load!(ScratchRepo, kase)

      case kase["expected"] do
        %{"error" => expected} when not is_nil(expected) ->
          assert {:error, %Store.Invalid{} = error} = calculate(kase)
          assert error.message == expected["message"]
          assert error.details == expected["details"]
          assert DigestFixtures.digests(ScratchRepo, 14101) == kase["before"]

        expected ->
          assert {:ok, id} = calculate(kase)
          rows = Enum.map(expected["rows"], &Map.put(&1, "id", id))
          assert DigestFixtures.digests(ScratchRepo, 14101) == rows
      end

      assert [[0]] = rows("SELECT count(*) FROM public.job_outbox")
      assert [[0]] = rows("SELECT count(*) FROM phoenix.rails_commands")
      assert [[0]] = rows("SELECT count(*) FROM oban.oban_jobs")
    end
  end

  test "yearly public call defaults ambient bounds to Berlin without changing the UTC user fallback" do
    kase = DigestFixtures.case!("default_ambient_yearly")
    opts = DigestFixtures.options(kase)
    refute Keyword.has_key?(opts, :ambient_zone)
    refute Map.has_key?(opts[:env], "TIME_ZONE")
    DigestFixtures.load!(ScratchRepo, kase)
    context = Dawarich.Digests.Context.load!(ScratchRepo, 14101, opts)
    assert context.effective_zone == "UTC"
    assert {:ok, id} = calculate(kase)
    expected = Enum.map(kase["expected"]["rows"], &Map.put(&1, "id", id))
    assert DigestFixtures.digests(ScratchRepo, 14101) == expected
    countries = hd(expected)["time_spent_by_location"]["countries"]
    assert Enum.any?(countries, &(&1["name"] == "Inside ambient year"))
    refute Enum.any?(countries, &(&1["name"] == "Outside ambient year"))
  end

  test "failure rolls back digest writes and reports the original exception" do
    kase = DigestFixtures.case!("duplicates_yearly")
    assert {:ok, :ok} = ScratchRepo.transaction(fn -> DigestFixtures.load!(ScratchRepo, kase) end)

    on_exit(fn ->
      reset!(ScratchRepo)

      ScratchRepo.query!(
        "CREATE UNIQUE INDEX IF NOT EXISTS index_digests_on_user_year_period_type_monthless " <>
          "ON public.digests (user_id, year, period_type) WHERE month IS NULL"
      )
    end)

    before = DigestFixtures.digests(ScratchRepo, 14101)
    fault = %RuntimeError{message: "after digest DML"}

    after_store = fn id ->
      assert id == 14601
      assert DigestFixtures.digests(ScratchRepo, 14101) == kase["expected"]["rows"]
      assert DigestFixtures.digests(ScratchRepo, 14101) != before
      raise fault
    end

    assert calculate(kase, after_store: after_store) == {:error, fault}
    assert DigestFixtures.digests(ScratchRepo, 14101) == before
  end

  defp calculate(kase, extra \\ []) do
    call = kase["call"]
    opts = Keyword.merge(DigestFixtures.options(kase), extra)

    if call["kind"] == "monthly",
      do: Calculation.monthly(ScratchRepo, call["user_id"], call["year"], call["month"], opts),
      else: Calculation.yearly(ScratchRepo, call["user_id"], call["year"], opts)
  end
end
