defmodule Dawarich.Users.RecalculationDigestsTest do
  use Dawarich.JobsCase

  alias Dawarich.RecalculationFixtures, as: Fixtures
  alias Dawarich.Users.Recalculation

  setup do
    pool =
      start_supervised!({ScratchRepo, [name: nil, pool_size: 2, parameters: [timezone: "UTC"]]},
        id: :utc_digests
      )

    ScratchRepo.put_dynamic_repo(pool)
    on_exit(fn -> ScratchRepo.put_dynamic_repo(ScratchRepo) end)
    start_oban(:recalculation_digests)
    :ok
  end

  test "calculates yearly digests after all parent dispatches without email" do
    for id <- ~w(user_all user_specific user_tokyo user_dst user_zero user_no_data) do
      reset!(ScratchRepo)
      source = Fixtures.case!(id)
      Fixtures.load!(ScratchRepo, source)
      parent = self()

      opts = options() ++ [phase: fn kind, year, _ -> send(parent, {kind, year}) end]
      assert {:ok, _} = Recalculation.run(ScratchRepo, :recalculation_digests, args(source), opts)

      expected =
        for call <- source["expected"]["calls"], call["kind"] in ~w(tracks digest) do
          year =
            if call["kind"] == "tracks",
              do: DateTime.from_unix!(call["start_timestamp"] + 86_400).year,
              else: Enum.at(call["args"], 1)

          {String.to_existing_atom(call["kind"]), year}
        end

      assert events() == expected, id
      actual = Dawarich.DigestFixtures.digests(ScratchRepo, 170_101)

      assert Enum.map(actual, &metadata/1) ==
               Enum.map(source["expected"]["rows"]["digests"], &metadata/1),
             id

      assert Enum.all?(actual, &(&1["sent_at"] == nil))
      assert rows("SELECT count(*) FROM notifications") == [[0]]

      assert rows(
               "SELECT count(*) FROM phoenix.rails_commands WHERE kind LIKE 'mail.%' OR kind LIKE 'digests.email_%'"
             ) == [[0]]

      assert rows("SELECT count(*) FROM oban.oban_jobs WHERE worker LIKE '%Digests%'") == [[0]]
    end
  end

  test "raises the original digest error with originating stack after partial stats commits" do
    source = Fixtures.case!("user_digest_escape")
    Fixtures.load!(ScratchRepo, source)
    parent = self()

    fault = fn _ -> digest_origin() end

    opts =
      options() ++
        [
          digest_opts: [after_store: fault],
          phase: fn kind, year, _ -> send(parent, {kind, year}) end
        ]

    stack =
      try do
        Recalculation.run(ScratchRepo, :recalculation_digests, args(source), opts)
        flunk("digest failure was swallowed")
      rescue
        error in RuntimeError ->
          assert error.message == "synthetic recalculation failure"
          __STACKTRACE__
      end

    assert {__MODULE__, :digest_origin, _, _} = hd(stack)
    assert Enum.any?(stack, fn {module, _, _, _} -> module == Dawarich.Digests.Calculation end)
    assert rows("SELECT count(*) FROM stats") != [[0]]
    assert rows("SELECT count(*) FROM digests") == [[0]]
    assert rows("SELECT count(*) FROM phoenix.track_generations") == [[1]]
    assert events() == [tracks: 2025, digest: 2025]
    assert rows("SELECT count(*) FROM notifications") == [[0]]
  end

  defp digest_origin, do: raise("synthetic recalculation failure")

  defp metadata(row),
    do: Map.drop(row, ~w(id sharing_uuid created_at updated_at))

  defp args(source) do
    [id, options] = source["job"]["arguments"]
    %{"user_id" => id, "year" => options["year"], "source_job_id" => source["job"]["job_id"]}
  end

  defp options, do: [now: ~U[2026-10-03 12:00:00Z], env: %{"SELF_HOSTED" => "false"}]

  defp events do
    receive do
      {kind, _} = event when kind in [:tracks, :digest] -> [event | events()]
    after
      0 -> []
    end
  end
end
