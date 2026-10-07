defmodule Dawarich.Places.OrphanCleanupWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 26,
    unique: [keys: [:event_id, :cursor], period: :infinity, states: :all]

  alias Dawarich.Jobs.{Ownership, Processed}
  alias Dawarich.Places.Orphans
  @key "command:places.orphan_cleanup"

  def args_from_command(1, %{"user_id" => user} = p)
      when map_size(p) == 1 and is_integer(user) and
             user in -9_223_372_036_854_775_808..9_223_372_036_854_775_807,
      do: {:ok, Map.put(p, "cursor", 0)}

  def args_from_command(1, _), do: {:error, "invalid_payload"}
  def args_from_command(_, _), do: {:error, "unsupported_version"}

  def batch_id(args) do
    <<a::48, _::4, b::12, _::2, c::62, _::binary>> =
      :crypto.hash(
        :sha,
        Ecto.UUID.dump!(args["event_id"]) <> "places.orphan_cleanup:#{args["cursor"]}"
      )

    Ecto.UUID.load!(<<a::48, 5::4, b::12, 2::2, c::62>>)
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, conf: conf}), do: run(Dawarich.Jobs.repo(), conf.name, args)

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    count = attempt - 1
    Integer.pow(count, 4) + 15 + :rand.uniform(10 * (count + 1)) - 1
  end

  def run(repo, oban, args, opts \\ []) do
    {:ok, :ok} =
      repo.transaction(fn ->
        owner = if args["cursor"] == 0, do: :oban, else: Ownership.lock(repo, @key)

        if Processed.claim!(repo, batch_id(args), "places.orphan_cleanup") do
          if owner == :oban do
            drain(repo, oban, args, opts)
          else
            Dawarich.RailsCommands.insert!(repo, "places_orphan_cleanup", %{
              "user_id" => args["user_id"]
            })
          end
        end

        :ok
      end)

    :ok
  end

  defp drain(repo, oban, args, opts) do
    ids =
      repo.query!(
        """
        SELECT p.id FROM places p JOIN users u ON u.id=p.user_id
        WHERE u.deleted_at IS NULL AND p.user_id=$1 AND p.id>$2 AND p.source=1 AND (p.note IS NULL OR p.note='')
          AND NOT EXISTS(SELECT 1 FROM visits v WHERE v.place_id=p.id)
          AND NOT EXISTS(SELECT 1 FROM place_visits pv WHERE pv.place_id=p.id)
          AND NOT EXISTS(SELECT 1 FROM taggings t WHERE t.taggable_id=p.id AND t.taggable_type='Place')
        ORDER BY p.id LIMIT 500
        """,
        [args["user_id"], args["cursor"]],
        log: false
      ).rows
      |> List.flatten()

    hook = Keyword.get(opts, :hook, fn _ -> :ok end)
    hook.({:selected, ids})

    Orphans.delete_batch(repo, args["user_id"], ids)
    Enum.each(ids, &hook.({:deleting, &1}))

    if length(ids) == 500, do: Oban.insert!(oban, new(Map.put(args, "cursor", List.last(ids))))
    :ok
  end
end
