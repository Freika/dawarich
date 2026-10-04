defmodule Dawarich.Users.RecalculationStatsTest do
  use Dawarich.JobsCase

  alias Dawarich.RecalculationFixtures, as: Fixtures
  alias Dawarich.Stats.CalculateMonth
  alias Dawarich.Users.Recalculation

  setup do
    pool =
      start_supervised!({ScratchRepo, [name: nil, pool_size: 2, parameters: [timezone: "UTC"]]},
        id: :utc_stats
      )

    ScratchRepo.put_dynamic_repo(pool)
    on_exit(fn -> ScratchRepo.put_dynamic_repo(ScratchRepo) end)
    start_oban(:recalculation_stats)
    :ok
  end

  test "runs all twelve months for all source years before any track parent" do
    for id <- ~w(user_all user_specific user_no_data user_missing user_deleted) do
      reset!(ScratchRepo)
      source = Fixtures.case!(id)
      Fixtures.load!(ScratchRepo, source)
      parent = self()

      options =
        options(source) ++
          [
            before_month: fn year, month, state ->
              send(parent, {:month, year, month, state.locale})
            end,
            phase: fn kind, year, _state -> send(parent, {:phase, kind, year}) end
          ]

      assert {:ok, _} =
               Recalculation.run(ScratchRepo, :recalculation_stats, args(source), options)

      expected =
        for call <- source["expected"]["calls"],
            call["kind"] == "stats",
            do: {:month, Enum.at(call["args"], 1), Enum.at(call["args"], 2), call["locale"]}

      years = expected |> Enum.map(&elem(&1, 1)) |> Enum.uniq()

      assert events() ==
               expected ++
                 Enum.map(years, &{:phase, :tracks, &1}) ++
                 Enum.map(years, &{:phase, :digest, &1})

      assert stats() == source_stats(source), id
    end
  end

  test "continues handled stats errors in saved locale but propagates escaping errors" do
    source = Fixtures.case!("user_stats_handled")
    Fixtures.load!(ScratchRepo, source)
    parent = self()

    fault = fn repo, user_id, _year, _month, opts ->
      CalculateMonth.call(
        repo,
        user_id,
        2025,
        3,
        Keyword.put(opts, :hexagons, fn _, _, _, _ ->
          raise "synthetic recalculation failure"
        end)
      )
    end

    opts =
      options(source) ++
        [
          stats: fault,
          before_month: fn year, month, state ->
            send(parent, {:month, year, month, state.locale})
          end,
          phase: fn kind, year, _ -> send(parent, {:phase, kind, year}) end
        ]

    assert {:ok, _} = Recalculation.run(ScratchRepo, :recalculation_stats, args(source), opts)
    for month <- 1..12, do: assert_receive({:month, 2025, ^month, "fr"})
    assert_receive {:phase, :tracks, 2025}
    assert_receive {:phase, :digest, 2025}

    messages =
      rows("SELECT kind,title,content FROM notifications WHERE user_id=$1 ORDER BY id", [170_101])

    assert length(messages) == 12
    [kind, title, _] = hd(source["expected"]["notifications"])

    for [actual_kind, actual_title, content] <- messages do
      assert Dawarich.Notifications.kind_name(actual_kind) == kind
      assert actual_title == title
      assert content =~ "synthetic recalculation failure"
    end

    assert stats() == []

    escaping = fn _year, _month, _state -> raise "synthetic escaping failure" end

    assert_raise RuntimeError, "synthetic escaping failure", fn ->
      Recalculation.run(
        ScratchRepo,
        :recalculation_stats,
        args(source),
        Keyword.put(options(source), :before_month, escaping)
      )
    end

    refute_receive {:phase, _, _}

    nested = Fixtures.case!("user_nested_argument")

    hook = fn year, month, state ->
      send(parent, {:zone, year, month, state.zone})

      if month == 2 and state.zone == "Europe/Berlin",
        do: raise(ArgumentError, "synthetic nested argument")
    end

    assert {:ok, %{zone: "Etc/UTC"}} =
             Recalculation.run(
               ScratchRepo,
               :recalculation_stats,
               args(nested),
               Keyword.put(options(nested), :before_month, hook)
             )

    for call <- nested["expected"]["calls"], call["kind"] == "stats" do
      [_, year, month] = call["args"]
      zone = if call["zone"] == "UTC", do: "Etc/UTC", else: call["zone"]
      assert_receive {:zone, ^year, ^month, ^zone}
    end
  end

  defp args(source) do
    [id, options] = source["job"]["arguments"]
    %{"user_id" => id, "year" => options["year"], "source_job_id" => source["job"]["job_id"]}
  end

  defp options(_source), do: [now: ~U[2026-10-03 12:00:00Z], env: %{"SELF_HOSTED" => "false"}]

  defp events do
    receive do
      {:month, _, _, _} = event -> [event | events()]
      {:phase, _, _} = event -> [event | events()]
    after
      0 -> []
    end
  end

  defp stats,
    do:
      rows(
        "SELECT year,month,distance,daily_distance,flight_distance,toponyms,h3_hex_ids,calculation_version FROM stats ORDER BY year,month"
      )

  defp source_stats(source),
    do:
      source["expected"]["rows"]["stats"]
      |> Enum.sort_by(&{&1["year"], &1["month"]})
      |> Enum.map(fn row ->
        Enum.map(
          ~w(year month distance daily_distance flight_distance toponyms h3_hex_ids calculation_version),
          &row[&1]
        )
      end)
end
