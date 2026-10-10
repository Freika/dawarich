defmodule Dawarich.Cache.PagesTest do
  use Dawarich.DataCase, async: true
  alias Dawarich.Cache.{Pages, PagesCodec}
  alias Dawarich.Test.{FrameSeeds, NativePageCache}
  alias Dawarich.Accounts.Scope

  setup do
    {:ok, cache} = NativePageCache.start()
    scope = Scope.for_user(FrameSeeds.user!(8811, %{"timezone" => "UTC"}), "de")
    %{cache: cache, scope: scope, opts: NativePageCache.options(cache)}
  end

  test "native cache expiry and payload bounds are explicit", %{
    scope: scope,
    cache: cache,
    opts: opts
  } do
    reader = fn _ ->
      send(self(), :read)
      {:ok, %{state: :ready, distance: 12}}
    end

    assert {:ok, %{distance: 12}} =
             Pages.fetch(scope, :summary, %{"year" => "2025"}, reader, opts)

    assert_receive :read

    assert {:ok, %{distance: 12}} =
             Pages.fetch(scope, :summary, %{"year" => "2025"}, reader, opts)

    refute_receive :read, 0
    assert Enum.any?(NativePageCache.commands(cache), &match?(["SET", _, _, "EX", "86400"], &1))
    assert {:ok, _} = Pages.fetch(scope, :patterns, %{"year" => "2025"}, reader, opts)
    assert_receive :read
    assert Enum.any?(NativePageCache.commands(cache), &match?(["SET", _, _, "EX", "3600"], &1))
    NativePageCache.advance(cache, 86401)
    assert {:ok, _} = Pages.fetch(scope, :summary, %{"year" => "2025"}, reader, opts)
    assert_receive :read

    assert {:error, :invalid_payload} =
             PagesCodec.encode(%{blob: String.duplicate("x", 1_048_577)})

    assert {:error, :invalid_payload} = PagesCodec.decode(<<131, 80, 0, 16, 0, 0, 120, 156>>)

    assert {:error, :invalid_payload} =
             PagesCodec.decode(:erlang.term_to_binary(fn -> :unsafe end))

    unknown = "native_uninterned_" <> Ecto.UUID.generate()

    assert {:error, :invalid_payload} =
             PagesCodec.decode(<<131, 100, byte_size(unknown)::16, unknown::binary>>)

    assert {:error, :invalid_payload} =
             PagesCodec.encode(%{rows: List.duplicate(String.duplicate("x", 40000), 30)})

    assert {:error, :invalid_payload} = PagesCodec.encode(%{api_key: "synthetic-private"})
    assert {:ok, bytes} = PagesCodec.encode(%{date: ~D[2025-03-30], data: [[1, 2]]})
    assert {:ok, %{date: ~D[2025-03-30], data: [[1, 2]]}} = PagesCodec.decode(bytes)
    before = map_size(NativePageCache.entries(cache))

    assert {:ok, _} =
             Pages.fetch(
               scope,
               :oversized,
               %{},
               fn _ -> {:ok, %{blob: String.duplicate("x", 1_048_577)}} end,
               opts
             )

    assert map_size(NativePageCache.entries(cache)) == before
    NativePageCache.failure(cache, :ttl)

    assert {:ok, %{distance: 7}} =
             Pages.fetch(scope, :failure, %{}, fn _ -> {:ok, %{distance: 7}} end, opts)

    assert map_size(NativePageCache.entries(cache)) == before
  end

  test "a cancelled old generation cannot repopulate an invalidated cache", %{
    scope: scope,
    cache: cache,
    opts: opts
  } do
    stale = fn _ ->
      Dawarich.State.bump_epochs(Repo, ["cache:user:#{scope.user.id}"])
      {:ok, %{distance: 1}}
    end

    assert {:error, :stale} = Pages.fetch(scope, :summary, %{}, stale, opts)
    assert NativePageCache.entries(cache) == %{}

    assert {:ok, %{distance: 2}} =
             Pages.fetch(scope, :summary, %{}, fn _ -> {:ok, %{distance: 2}} end, opts)

    assert map_size(NativePageCache.entries(cache)) == 1
    writes = self()

    delayed =
      Keyword.put(opts, :after_commit, fn write -> send(writes, {:after_commit, write}) end)

    assert {:ok, _} =
             Pages.fetch(scope, :delayed, %{}, fn _ -> {:ok, %{distance: 3}} end, delayed)

    assert map_size(NativePageCache.entries(cache)) == 1
    assert_receive {:after_commit, write}
    Dawarich.State.bump_epochs(Repo, ["cache:user:#{scope.user.id}"])
    write.()
    assert map_size(NativePageCache.entries(cache)) == 1
  end

  test "corrupt cache falls back to a bounded ready read or pending state", %{
    scope: scope,
    cache: cache,
    opts: opts
  } do
    assert {:ok, %{state: :ready}} =
             Pages.fetch(scope, :patterns, %{}, fn _ -> {:ok, %{state: :ready}} end, opts)

    [key] = Map.keys(NativePageCache.entries(cache))
    NativePageCache.corrupt(cache, key, <<131, 104, 2, 100>>)

    assert {:ok, %{state: :pending}} =
             Pages.fetch(scope, :patterns, %{}, fn _ -> {:ok, %{state: :pending}} end, opts)

    NativePageCache.failure(cache, :read)

    assert {:ok, %{state: :ready}} =
             Pages.fetch(scope, :patterns, %{}, fn _ -> {:ok, %{state: :ready}} end, opts)

    Repo.query!(
      "UPDATE users SET encrypted_password='changed-session-00000000000000000' WHERE id=$1",
      [scope.user.id],
      log: false
    )

    assert {:error, :stale_session} =
             Pages.fetch(
               scope,
               :patterns,
               %{},
               fn _ -> flunk("stale owner reached read") end,
               opts
             )
  end

  test "native summaries stay warm for one day and pending projections never hide completion", %{
    scope: scope,
    cache: cache,
    opts: opts
  } do
    reader = fn _ ->
      send(self(), :read)
      {:ok, %{state: :ready, distance: 1}}
    end

    assert {:ok, _} = Pages.fetch(scope, :summary, %{"year" => "2025"}, reader, opts)
    assert_receive :read
    NativePageCache.advance(cache, 3601)
    assert {:ok, _} = Pages.fetch(scope, :summary, %{"year" => "2025"}, reader, opts)
    refute_receive :read, 0

    assert {:ok, %{state: :pending}} =
             Pages.fetch(scope, :patterns, %{}, fn _ -> {:ok, %{state: :pending}} end, opts)

    assert {:ok, %{state: :ready}} =
             Pages.fetch(scope, :patterns, %{}, fn _ -> {:ok, %{state: :ready}} end, opts)

    assert {:ok, _} = Pages.fetch(scope, :counts, %{}, fn _ -> {:ok, %{total: 0}} end, opts)

    Repo.query!(
      "INSERT INTO phoenix.stats_point_counts (user_id,geocoded,without_data,computed_at) VALUES ($1,7,0,$2)",
      [scope.user.id, ~U[2026-10-01 12:00:00Z]],
      log: false
    )

    assert {:ok, %{total: 7}} =
             Pages.fetch(scope, :counts, %{}, fn _ -> {:ok, %{total: 7}} end, opts)
  end

  for change <- [:deletion, :identity, :revision] do
    @tag cache_return: true
    test "private cache miss refuses #{change} during SET", %{
      scope: scope,
      cache: cache,
      opts: opts
    } do
      command = fn args ->
        result = NativePageCache.command(cache, args)

        if hd(args) == "SET" do
          case unquote(change) do
            :deletion ->
              rows("UPDATE users SET deleted_at=now() WHERE id=$1", [scope.user.id])

            :identity ->
              rows(
                "UPDATE users SET encrypted_password='changed-synthetic-cache-identity' WHERE id=$1",
                [scope.user.id]
              )

            :revision ->
              Dawarich.State.bump_epochs(Repo, ["cache:user:#{scope.user.id}"])
          end
        end

        result
      end

      expected = if unquote(change) == :revision, do: :stale, else: :stale_session

      assert {:error, ^expected} =
               Pages.fetch(
                 scope,
                 :summary,
                 %{},
                 fn _ -> {:ok, %{distance: 42}} end,
                 Keyword.put(opts, :command, command)
               )

      assert Enum.any?(NativePageCache.commands(cache), &match?(["SET" | _], &1))
      assert NativePageCache.entries(cache) == %{}
    end
  end
end
