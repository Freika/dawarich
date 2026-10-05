defmodule Dawarich.Geocoding.NightlySweep do
  @moduledoc false

  alias Dawarich.{RailsCommands, State}
  alias Dawarich.Geocoding.{Config, NightlyWorker, ReversePointWorker}
  alias Dawarich.Jobs.{Ownership, Processed}

  @namespace <<0x6B, 0xA7, 0xB8, 0x11, 0x9D, 0xAD, 0x11, 0xD1, 0x80, 0xB4, 0x00, 0xC0, 0x4F, 0xD4,
               0x30, 0xC8>>
  @points "SELECT id, user_id FROM points WHERE id > $1 AND reverse_geocoded_at IS NULL ORDER BY id LIMIT 1000"

  def root_id(slot), do: uuid(@namespace, "geocoding.nightly:cron:#{slot}")
  def receipt_id(root, id), do: uuid(Ecto.UUID.dump!(root), "scheduled:#{id}")

  def child_id(root, user, ids),
    do: uuid(Ecto.UUID.dump!(root), "reverse:#{user}:#{Enum.join(ids, ",")}")

  def run(repo, oban, args, opts \\ []) do
    env = Keyword.get_lazy(opts, :env, &System.get_env/0)

    if Config.resolve(repo, env).enabled do
      case Ownership.with_owner(repo, NightlyWorker.key(), :oban, fn ->
             batch(repo, oban, args, opts)
           end) do
        {:ok, :ok} ->
          :ok

        {:skip, _} ->
          finish_accepted(repo, args)
          {:cancel, :not_owner}

        {:error, reason} ->
          {:error, reason}
      end
    else
      finish_accepted(repo, args)
      :ok
    end
  end

  defp batch(repo, oban, args, opts) do
    root = root_id(args["slot"])

    unless Processed.done?(repo, root) do
      rows = repo.query!(@points, [args["after_id"]], log: false).rows
      owner = Ownership.lock(repo, "command:geocoding.reverse_point")

      selected =
        Enum.filter(rows, fn [id, _] ->
          Processed.claim!(repo, receipt_id(root, id), "geocoding.nightly")
        end)

      State.unclaim_all(repo, Enum.map(selected, fn [id, _] -> "geocode:enq:Point:#{id}" end))

      selected
      |> Enum.group_by(&List.last/1, &hd/1)
      |> Enum.sort_by(fn {_user, ids} -> hd(ids) end)
      |> Enum.each(fn {user, ids} ->
        for chunk <- Enum.chunk_every(ids, 100) do
          payload = %{"user_id" => user, "point_ids" => chunk, "force" => true}
          publish(repo, oban, payload, child_id(root, user, chunk), owner)
        end

        Keyword.get(opts, :hook, fn _ -> :ok end).(user)
      end)

      affected =
        Enum.uniq(args["affected_user_ids"] ++ Enum.map(selected, &List.last/1)) |> Enum.sort()

      if length(rows) == 1000 do
        next =
          Map.merge(args, %{
            "after_id" => rows |> List.last() |> hd(),
            "affected_user_ids" => affected
          })

        Oban.insert!(oban, NightlyWorker.new(next))
      else
        finish!(repo, root, affected)
      end
    end

    :ok
  end

  defp finish_accepted(_repo, %{"affected_user_ids" => []}), do: :ok

  defp finish_accepted(repo, args) do
    repo.transaction(fn -> finish!(repo, root_id(args["slot"]), args["affected_user_ids"]) end)
  end

  defp finish!(repo, root, affected) do
    if Processed.claim!(repo, root, "geocoding.nightly") do
      for user <- affected do
        RailsCommands.insert!(repo, "stats.caches_invalidated", %{
          "user_id" => user,
          "year" => nil,
          "scope" => "all"
        })
      end
    end
  end

  defp publish(_repo, oban, payload, event, :oban) do
    {:ok, decoded} = ReversePointWorker.args_from_command(1, payload)
    Oban.insert!(oban, ReversePointWorker.new(Map.put(decoded, "event_id", event)))
  end

  defp publish(repo, _oban, payload, event, :sidekiq),
    do:
      RailsCommands.insert!(repo, "geocoding.reverse_point", Map.put(payload, "event_id", event))

  defp uuid(namespace, name) do
    <<a::48, _::4, b::12, _::2, c::62, _::binary>> = :crypto.hash(:sha, namespace <> name)
    Ecto.UUID.load!(<<a::48, 5::4, b::12, 2::2, c::62>>)
  end
end
