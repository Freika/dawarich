defmodule Dawarich.ReleaseJobs.FamilyBackfill do
  @moduledoc false
  use Oban.Worker, queue: :maintenance, priority: 3, max_attempts: 26

  alias Dawarich.Families.{AutoCreateWorker, MemberSync}
  alias Dawarich.ReleaseOperations

  @families """
  SELECT u.id FROM users u
  WHERE u.deleted_at IS NULL AND u.plan=2 AND u.id>$1
    AND NOT EXISTS(SELECT 1 FROM family_memberships m WHERE m.user_id=u.id)
    AND NOT EXISTS(SELECT 1 FROM families f WHERE f.creator_id=u.id)
  ORDER BY u.id LIMIT 500
  """
  @entitlements "SELECT id FROM families WHERE id>$1 ORDER BY id LIMIT 200"
  @max_id 9_223_372_036_854_775_807
  @keys ~w(version cursor operation_id event_id)

  def command_type, do: "release.family_backfill"

  def args_from_command(1, %{"phase" => phase, "after_id" => id, "time_zone" => zone} = payload)
      when map_size(payload) == 3 and phase in ["families", "entitlements"] and
             is_integer(id) and id >= 0 and id <= @max_id and is_binary(zone) do
    Dawarich.Imports.ZonePeriod.load!(zone)
    {:ok, %{"version" => 1, "cursor" => payload}}
  rescue
    _ -> {:error, "invalid_payload"}
  end

  def args_from_command(1, _), do: {:error, "invalid_payload"}
  def args_from_command(_, _), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"version" => version, "cursor" => cursor} = args} = job) do
    with true <- Enum.all?(Map.keys(args), &(&1 in @keys)),
         {:ok, _} <- args_from_command(version, cursor),
         {:ok, args} <- identities(args),
         true <- bound?(Dawarich.Jobs.repo(), %{job | args: args}) do
      oban = if job.conf, do: job.conf.name, else: Oban

      ReleaseOperations.run(Dawarich.Jobs.repo(), oban, __MODULE__, %{job | args: args},
        fail_on_error: true
      )
    else
      {:error, "unsupported_version"} -> {:cancel, :unsupported_version}
      _ -> {:cancel, :invalid_payload}
    end
  end

  def perform(%Oban.Job{}), do: {:cancel, :invalid_payload}

  defp identities(args) do
    case Map.take(args, ~w(operation_id event_id)) do
      ids when map_size(ids) > 0 ->
        Enum.reduce_while(ids, {:ok, args}, fn {key, id}, {:ok, normalized} ->
          with true <- is_binary(id) and byte_size(id) == 36,
               {:ok, uuid} <- Ecto.UUID.cast(id) do
            {:cont, {:ok, Map.put(normalized, key, uuid)}}
          else
            _ -> {:halt, :error}
          end
        end)

      _ ->
        :error
    end
  end

  defp bound?(repo, %{args: args, id: id} = job) do
    binding = job_binding(repo, job)

    binding != false and event_binding?(repo, args, id, binding) and
      operation_binding?(repo, args)
  end

  defp job_binding(_repo, %{id: nil}), do: :unrecorded

  defp job_binding(repo, %{id: id, args: args}) do
    case repo.query!("SELECT worker,args,state FROM oban.oban_jobs WHERE id=$1", [id], log: false).rows do
      [["Dawarich.ReleaseJobs.FamilyBackfill", stored, state]]
      when state in ~w(available scheduled executing retryable suspended completed) ->
        identities(stored) == {:ok, args}

      _ ->
        false
    end
  end

  defp event_binding?(repo, %{"event_id" => event, "cursor" => cursor}, id, binding) do
    case repo.query!(
           "SELECT command_type,command_version,payload,state,oban_job_id FROM job_outbox WHERE event_id=$1",
           [Ecto.UUID.dump!(event)],
           log: false
         ).rows do
      [["release.family_backfill", 1, ^cursor, "dispatched", job_id]] ->
        is_nil(id) or id == job_id

      [] ->
        binding == true

      _ ->
        false
    end
  end

  defp event_binding?(_repo, _args, _id, _binding), do: true

  defp operation_binding?(repo, args) do
    id = args["operation_id"] || args["event_id"]
    cursor = args["cursor"]

    case repo.query!(
           "SELECT command_type,cursor,status FROM phoenix.release_operations WHERE id=$1",
           [Ecto.UUID.dump!(id)],
           log: false
         ).rows do
      [] ->
        true

      [["release.family_backfill", stored, state]] when state in ~w(running failed completed) ->
        match?({:ok, _}, args_from_command(1, stored)) and
          Map.drop(stored, ["after_id"]) == Map.drop(cursor, ["after_id"]) and
          cursor["after_id"] <= stored["after_id"]

      _ ->
        false
    end
  end

  def step(repo, %{cursor: %{"phase" => "families", "after_id" => after_id} = cursor} = op) do
    ReleaseOperations.commit(repo, op, fn ->
      ids = ReleaseOperations.ids(repo, @families, [after_id])

      for id <- ids do
        Oban.insert!(
          op.oban,
          AutoCreateWorker.new(%{
            "event_id" => Ecto.UUID.generate(),
            "user_id" => id,
            "time_zone" => cursor["time_zone"]
          })
        )
      end

      advance(cursor, ids, 500)
    end)
  end

  def step(repo, %{cursor: %{"phase" => "entitlements", "after_id" => after_id} = cursor} = op) do
    ids = ReleaseOperations.ids(repo, @entitlements, [after_id])

    for id <- ids,
        do: MemberSync.run(repo, id, notify: false, time_zone: cursor["time_zone"])

    ReleaseOperations.commit(repo, op, fn -> advance(cursor, ids, 200) end)
  end

  defp advance(cursor, ids, size) do
    if length(ids) < size, do: :done, else: {%{cursor | "after_id" => List.last(ids)}, 0}
  end
end
