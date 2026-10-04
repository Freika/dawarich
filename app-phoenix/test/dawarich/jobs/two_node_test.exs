defmodule Dawarich.Jobs.TwoNodeTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db

  alias Dawarich.TwoNodeHarness

  defp start_node(node, opts \\ []) do
    args = Enum.flat_map(:code.get_path(), &[~c"-pa", &1])
    {:ok, peer, _} = :peer.start_link(%{connection: :standard_io, args: args})
    Process.unlink(peer)
    on_exit(fn -> if Process.alive?(peer), do: :peer.stop(peer) end)
    expected = Keyword.get(opts, :expected, :ok)
    prefix = Keyword.get(opts, :prefix, "oban")

    assert ^expected =
             :peer.call(
               peer,
               TwoNodeHarness,
               :boot,
               [Dawarich.ScratchRepo.config(), node, prefix],
               60_000
             )

    peer
  end

  defp leaders(peers), do: Enum.filter(peers, &:peer.call(&1, TwoNodeHarness, :leader?, []))

  defp cron_jobs,
    do:
      rows(
        "SELECT count(*) FROM oban.oban_jobs WHERE worker = 'Dawarich.TwoNodeHarness.CronWorker'"
      )

  test "two BEAMs with distinct Oban nodes elect one leader and insert one cron job per evaluation" do
    peers = [start_node("web-a"), start_node("web-b")]

    assert length(leaders(peers)) == 1
    assert [[node]] = rows("SELECT node FROM oban.oban_peers WHERE name = 'Dawarich.TwoNodeOban'")
    assert node in ["web-a", "web-b"]

    for peer <- peers, do: :ok = :peer.call(peer, TwoNodeHarness, :evaluate_cron, [])

    assert cron_jobs() == [[1]]
  end

  test "boot reports a failed database election instead of admitting a nonleader" do
    peer =
      start_node("failed-election",
        prefix: "two_node_missing_schema",
        expected: {:error, :election_failed}
      )

    refute :peer.call(peer, TwoNodeHarness, :leader?, [])
  end

  test "identical node names make both BEAMs leaders" do
    peers = [start_node("same"), start_node("same")]

    assert length(leaders(peers)) == 2

    for peer <- peers, do: :ok = :peer.call(peer, TwoNodeHarness, :evaluate_cron, [])

    assert cron_jobs() == [[2]]
  end
end
