defmodule Dawarich.CablePgTest do
  use Dawarich.JobsCase, async: false

  alias Dawarich.Cable
  alias Dawarich.Cable.{Bus, Frames}
  alias Dawarich.ScratchCaseRepo
  alias Dawarich.Test.A12a

  setup do
    reset!(ScratchCaseRepo)
    cable = Application.get_env(:dawarich, :cable)
    jobs = Application.get_env(:dawarich, :jobs_repo)
    Application.put_env(:dawarich, :cable, transport: :pg, bus: false)

    on_exit(fn ->
      Application.put_env(:dawarich, :cable, cable)
      Application.put_env(:dawarich, :jobs_repo, jobs)
    end)

    :ok
  end

  test "PG preserves every recorded producer broadcasting and payload byte" do
    prefix = Application.get_env(:dawarich, :cable_prefix)

    on_exit(fn ->
      Application.put_env(:dawarich, :cable_prefix, prefix)
      :persistent_term.erase({Bus, :prefix})
    end)

    producers = A12a.producer_inputs()
    oversized = {"large", ~s({ "html": "#{String.duplicate("München", 2_000)}" })}
    entries = Enum.map(producers, &{&1["broadcasting"], &1["payload"]}) ++ [oversized]
    assert byte_size(elem(oversized, 1)) > 8_192

    for namespace <- [nil, "producer_bytes"] do
      Application.put_env(:dawarich, :cable_prefix, namespace)
      :persistent_term.erase({Bus, :prefix})
      Application.put_env(:dawarich, :cable, transport: :pg, repo: ScratchRepo, polling: false)
      [spec] = Bus.child_specs()
      start_supervised!(spec)

      for broadcasting <- entries |> Enum.map(&elem(&1, 0)) |> Enum.uniq() do
        {:ok, ref} = Bus.subscribe(broadcasting)
        assert_receive {:cable_pg, _, _, :subscribed, ^broadcasting, ^ref} = ack
        assert Bus.event(ack) == {:subscribed, broadcasting}
      end

      for {{broadcasting, payload}, seq} <- Enum.with_index(entries, 1) do
        assert {:ok, ^seq} = Bus.publish(broadcasting, payload)
      end

      send(Bus, :poll)
      :sys.get_state(Bus)

      for {{broadcasting, payload}, seq} <- Enum.with_index(entries, 1) do
        assert_receive {:cable_pg, _, _, ^broadcasting, ^seq, ^payload} = message
        assert Bus.event(message) == {:message, broadcasting, payload}
      end

      refute_received {:cable_pg, _, _, _, _, _}

      for broadcasting <- entries |> Enum.map(&elem(&1, 0)) |> Enum.uniq(),
          do: Bus.unsubscribe(broadcasting)

      stop_supervised!(Bus)
    end
  end

  test "public Cable publication forwards the caller repo and preserves payload and error results" do
    Application.put_env(:dawarich, :jobs_repo, ScratchCaseRepo)
    producer = hd(A12a.corpus()["producers"])
    parts = A12a.streamables(producer["streamables"])
    message = A12a.term(producer["input"])
    stream = [{:user, 7}, "notifications"]

    turbo =
      ~s(<turbo-stream action="append" target="target"><template>native</template></turbo-stream>)

    refresh = ~s(<turbo-stream action="refresh"></turbo-stream>)
    raw = <<0, 255, 1>>

    assert {:error, :undo} =
             ScratchRepo.transaction(fn ->
               assert :ok =
                        Cable.broadcast_to(producer["channel"], parts, message, repo: ScratchRepo)

               assert :ok = Cable.turbo(stream, "append", "target", "native", repo: ScratchRepo)
               assert :ok = Cable.refresh(stream, repo: ScratchRepo)
               assert {:ok, 4} = Bus.publish("raw", raw, repo: ScratchRepo)

               send(
                 self(),
                 {:stored, rows("SELECT channel, payload FROM phoenix.cable_events ORDER BY seq")}
               )

               ScratchRepo.rollback(:undo)
             end)

    assert ScratchCaseRepo.query!("SELECT count(*) FROM phoenix.cable_events", [], log: false).rows ==
             [[0]]

    assert rows("SELECT count(*) FROM phoenix.cable_events") == [[0]]
    assert_receive {:stored, stored}

    expected = [
      [producer["broadcasting"], producer["payload"]],
      [Dawarich.RailsMessages.broadcasting(stream), Frames.payload(turbo)],
      [Dawarich.RailsMessages.broadcasting(stream), Frames.payload(refresh)],
      ["raw", raw]
    ]

    assert stored == expected

    Application.put_env(:dawarich, :jobs_repo, ScratchRepo)
    assert :ok = Cable.broadcast_to(producer["channel"], parts, message)
    assert :ok = Cable.turbo(stream, "append", "target", "native")
    assert :ok = Cable.refresh(stream)
    assert {:ok, 4} = Bus.publish("raw", raw)
    assert rows("SELECT channel, payload FROM phoenix.cable_events ORDER BY seq") == expected
    assert_raise RuntimeError, fn -> Bus.publish("raw", raw, repo: Dawarich.NotStartedRepo) end
    refute Process.whereis(Dawarich.Cable.Bus.Publisher)
  end
end
