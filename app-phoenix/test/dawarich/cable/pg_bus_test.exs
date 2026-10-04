defmodule Dawarich.Cable.PgBusTest do
  use Dawarich.JobsCase, async: false

  alias Dawarich.Cable.{Bus, PgStore}

  setup do
    cable = Application.get_env(:dawarich, :cable)
    prefix = Application.get_env(:dawarich, :cable_prefix)
    Application.put_env(:dawarich, :cable, transport: :pg, repo: ScratchRepo, polling: false)

    on_exit(fn ->
      Application.put_env(:dawarich, :cable, cable)
      Application.put_env(:dawarich, :cable_prefix, prefix)
      :persistent_term.erase({Bus, :prefix})
    end)

    :ok
  end

  test "subscription acknowledges its committed fence before any eligible message" do
    for prefix <- [nil, "pg_fence"] do
      Application.put_env(:dawarich, :cable_prefix, prefix)
      :persistent_term.erase({Bus, :prefix})
      [spec] = Bus.child_specs()
      start_supervised!(spec)
      namespace = prefix || ""
      broadcasting = "points"
      assert Bus.channel(broadcasting) == if(prefix, do: prefix <> ":points", else: "points")

      assert {:ok, 1} = PgStore.append(ScratchRepo, namespace, broadcasting, "old")
      assert {:ok, ref} = Bus.subscribe(broadcasting)
      assert_receive {:cable_pg, _, ^namespace, :subscribed, ^broadcasting, ^ref} = ack
      assert Bus.event(ack) == {:subscribed, broadcasting}

      assert {:ok, 2} = PgStore.append(ScratchRepo, namespace, broadcasting, "new")
      send(Bus, :poll)
      :sys.get_state(Bus)

      assert_receive {:cable_pg, _, ^namespace, ^broadcasting, 1, "old"} = old
      assert Bus.event(old) == :ignore
      assert_receive {:cable_pg, _, ^namespace, ^broadcasting, 2, "new"} = new
      assert Bus.event(new) == {:message, broadcasting, "new"}
      refute_received {:cable_pg, _, _, _, _, _}
      assert {:ok, _} = Bus.unsubscribe(broadcasting)
      stop_supervised!(Bus)
    end
  end
end
