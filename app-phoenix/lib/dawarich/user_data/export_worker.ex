defmodule Dawarich.UserData.ExportWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :exports,
    max_attempts: 1,
    unique: [keys: [:event_id], states: :incomplete, period: :infinity]

  alias Dawarich.UserData.{Export, ExportState, Commands}
  alias Dawarich.{Storage, State.Lease}

  def args_from_command(version, payload), do: Commands.export_args(version, payload)
  @impl Oban.Worker
  def timeout(_), do: :timer.hours(3)
  @impl Oban.Worker
  def perform(%Oban.Job{args: args}), do: run(Dawarich.Jobs.repo(), args)

  def run(repo, args, opts \\ []) do
    context = Keyword.get(opts, :context, %{})
    now = Map.get_lazy(context, :now, &NaiveDateTime.utc_now/0)

    case Lease.with_lease(
           repo,
           ExportState.lease_name(args),
           fn holder ->
             case ExportState.capture(repo, args, holder, now) do
               {:ok, :skip} -> :ok
               {:ok, state} -> generate(state, context, opts)
               {:error, :done} -> :ok
               {:error, :lost} -> {:cancel, :ownership_lost}
             end
           end,
           timeout_ms: 0
         ) do
      {:ok, result} -> result
      {:error, :timeout} -> {:cancel, :busy}
    end
  rescue
    ExportState.Lost -> {:cancel, :ownership_lost}
  end

  defp generate(state, context, opts) do
    context =
      Map.merge(
        %{
          repo: state.repo,
          zone: Dawarich.TimeZoneName.to_iana(state.args["time_zone"]),
          locale: state.args["locale"],
          now: state.now
        },
        context
      )

    context =
      context
      |> Map.put_new_lazy(:storage, &Dawarich.Imports.StorageContext.storage/0)
      |> Map.put_new_lazy(:storage_services, &Dawarich.Imports.StorageContext.services/0)

    dir = Storage.tmp_dir!(context.storage, state.args["event_id"])
    generate_archive(state, context, opts, dir)
  rescue
    error in ExportState.Lost ->
      reraise error, __STACKTRACE__

    error ->
      ExportState.fail!(state)
      reraise error, __STACKTRACE__
  end

  defp generate_archive(state, context, opts, dir) do
    try do
      archive = Export.write(state.repo, state.args["user_id"], dir, context)
      ExportState.effect!(state, fn -> :ok end)

      put =
        Keyword.get(opts, :put, fn storage, zip, name ->
          Storage.put!(storage, zip, name, "application/zip")
        end)

      blob = put.(context.storage, archive.path, state.name)

      try do
        ExportState.attach!(
          state,
          Map.put(
            blob,
            :stored_service,
            Map.get(context.storage, :stored_service, blob.service_name)
          )
        )
      rescue
        error in ExportState.Lost ->
          Storage.delete(context.storage, blob.key)
          reraise error, __STACKTRACE__
      end

      ExportState.status!(state, 2)
      notify = Keyword.get(opts, :notify, &Export.notify!/5)

      ExportState.finish!(state, fn ->
        notify.(state.repo, state.args["user_id"], archive.counts, state.locale, state.now)
      end)

      :ok
    after
      File.rm_rf(dir)
    end
  end
end
