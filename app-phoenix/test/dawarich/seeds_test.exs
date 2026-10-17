defmodule Dawarich.SeedsTest do
  use Dawarich.JobsCase

  alias Dawarich.A12hSeeds, as: Corpus
  alias Dawarich.Release

  setup do
    ScratchRepo.query!("DELETE FROM phoenix.release_migrator_leases", [], log: false)
    c = Corpus.case!("A12h_fresh")
    Corpus.load!(ScratchRepo, c["seed"], ~w(tags users countries regions))
    priv = Corpus.country_priv!(c["sources"]["countries"])
    asset = Path.join(priv, "regions.json")
    File.write!(asset, Jason.encode!(c["sources"]["regions"]))

    %{
      opts: [
        repo: ScratchRepo,
        env: %{
          "DAWARICH_PHOENIX_LIFECYCLE" => "true",
          "SELF_HOSTED" => "true",
          "DATABASE_ADVISORY_LOCKS" => "false"
        },
        now: Corpus.now(),
        priv_dir: priv,
        asset: asset,
        salt: "$2a$12$PhoenixA12eCorpusSaltu"
      ]
    }
  end

  test "standalone flag runs native release seeds idempotently without the lifecycle opt in", %{
    opts: opts
  } do
    options =
      Keyword.put(opts, :env, %{
        "DAWARICH_RAILS" => "off",
        "SELF_HOSTED" => "true",
        "DATABASE_ADVISORY_LOCKS" => "false"
      })

    assert Release.seed(options) == :ok
    assert rows("SELECT count(*) FROM users") == [[1]]
    before = snapshot()
    assert Release.seed(options) == :ok
    assert snapshot() == before
  end

  test "native seeds run in source order and a second call is unchanged", %{opts: opts} do
    assert Release.seed(opts) == :ok
    assert rows("SELECT count(*) FROM users") == [[1]]
    assert rows("SELECT count(*) FROM tags") == [[4]]
    before = snapshot()
    assert Release.seed(opts) == :ok
    assert snapshot() == before

    Corpus.load!(ScratchRepo, %{}, ~w(tags users countries regions))
    empty = Corpus.country_priv!(%{"type" => "FeatureCollection", "features" => []})

    assert_raise RuntimeError, "ordinary seeds refused", fn ->
      Release.seed(Keyword.put(opts, :priv_dir, empty))
    end

    assert rows("SELECT count(*) FROM users") == [[1]]
    assert rows("SELECT count(*) FROM tags") == [[0]]
    assert rows("SELECT count(*) FROM regions") == [[0]]
    assert rows("SELECT count(*) FROM countries") == [[0]]
  end

  test "concurrent native seeds serialize without duplicate initial records", %{opts: opts} do
    parent = self()

    random = fn size ->
      send(parent, {:seed_stage, self()})
      receive do: (:continue -> :binary.copy(<<1>>, size))
    end

    first = Task.async(fn -> Release.seed(Keyword.put(opts, :random_bytes, random)) end)
    assert_receive {:seed_stage, caller}, 5_000

    waiting = fn _ ->
      send(parent, {:lease_waiting, self()})
      receive do: (:continue -> :ok)
    end

    second = Task.async(fn -> Release.seed(Keyword.put(opts, :lease_sleep, waiting)) end)
    assert_receive {:lease_waiting, waiter}, 5_000
    send(caller, :continue)
    assert Task.await(first) == :ok
    send(waiter, :continue)
    assert Task.await(second) == :ok
    assert rows("SELECT count(*) FROM users") == [[1]]
    assert rows("SELECT count(*) FROM tags") == [[4]]
    assert rows("SELECT count(*) FROM phoenix.release_migrator_leases") == [[0]]
  end

  defp snapshot, do: Enum.map(~w(users countries regions tags), &Corpus.snapshot(ScratchRepo, &1))
end
