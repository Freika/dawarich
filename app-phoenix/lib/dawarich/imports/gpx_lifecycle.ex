defmodule Dawarich.Imports.GpxLifecycle do
  @moduledoc false
  alias Dawarich.Imports.{
    GpxArchive,
    GpxImporter,
    ImportMessages,
    ImportState,
    LeaseLost,
    Postprocessing,
    Progress,
    Tempfiles
  }

  alias Dawarich.{Notifications, Storage.Reader, Storage.ImportServices}
  require Logger

  def call(lease, context) do
    context = Map.put(context, :progress_lane, lease.lane)

    ImportState.with_snapshot(lease, fn state ->
      context = Map.put(context, :fence, fn fun -> ImportState.effect!(lease, fun) end)
      result = if state.mode == :terminal, do: :ok, else: process(lease, state, context)

      case result do
        {:legacy, _} = legacy ->
          legacy

        :ok ->
          finish(lease, context)
          :ok
      end
    end)
  end

  defp process(lease, state, context) do
    Tempfiles.with_files(fn adopt ->
      case prepare(lease, state, context, adopt) do
        {:gpx, path} -> run_import(lease, state, context, path)
        {:legacy, _} = legacy -> legacy
        {:error, error, stack} -> failure(lease, state.import, context, error, stack)
      end
    end)
  end

  defp prepare(lease, state, context, adopt) do
    blob = state.blob || raise(ArgumentError, "Import file attachment is missing")

    with {:ok, config} <- ImportServices.resolve(context.services, blob) do
      opts = [temp_dir: Map.get(context, :temp_dir, System.tmp_dir!()), on_verified: adopt]
      path = Reader.download!(config, blob, opts)
      ImportState.effect!(lease, fn -> :ok end)
      prepared = GpxArchive.prepare!(path, opts)
      ImportState.effect!(lease, fn -> :ok end)

      case prepared do
        {:gpx, path} -> admit_encoding(path)
        legacy -> legacy
      end
    end
  rescue
    error in LeaseLost -> reraise error, __STACKTRACE__
    error -> {:error, error, __STACKTRACE__}
  end

  defp admit_encoding(path) do
    File.open!(path, [:read, :binary], &Dawarich.Imports.XmlPreamble.read/1)
    {:gpx, path}
  rescue
    error in ArgumentError ->
      if error.message == "GPX parse error: unsupported or mismatched encoding",
        do: {:legacy, :unsupported_encoding},
        else: {:gpx, path}
  end

  defp run_import(lease, state, context, path) do
    try do
      context = Dawarich.Imports.GpxResume.driver(lease, state, context)
      Dawarich.Imports.GpxResume.start!(lease, state, context)
      publish(lease, context)
      driver = Map.put(context, :altitude_decimal?, altitude_decimal?(lease, context))
      GpxImporter.call(path, state.import, driver)
      Postprocessing.complete!(lease, state.import, context)
    rescue
      error in LeaseLost -> reraise error, __STACKTRACE__
      error -> failure(lease, state.import, context, error, __STACKTRACE__)
    end

    ImportState.complete!(lease, clock(context))

    :ok
  end

  defp finish(lease, context) do
    ImportState.effect!(lease, fn ->
      if ImportState.mode(lease) == :terminal do
        import = ImportState.import!(lease)

        if import.status == 2 do
          Postprocessing.enqueue_extraction!(lease.repo, import, context)
          publish(lease, context, false)
        end
      end

      Map.get(context, :on_terminal, fn -> :ok end).()
    end)

    broadcast(lease)
  end

  defp failure(lease, import, context, error, stack) do
    message = ImportMessages.failure(import, context, error, stack)

    ImportState.effect!(lease, fn ->
      ImportState.fail!(lease, error, clock(context))
      publish(lease, context, false)

      Notifications.create!(
        lease.repo,
        import.user_id,
        message.kind,
        message.title,
        message.content,
        DateTime.to_naive(clock(context))
      )

      ImportState.complete!(lease, clock(context))
    end)

    broadcast(lease)
    if report = Map.get(context, :report_error), do: report.(error, "Import failed")
    :ok
  end

  defp publish(lease, context, native? \\ true) do
    ImportState.effect!(lease, fn ->
      Progress.publish!(lease.repo, lease.import, context.locale, lease.lane)
    end)

    if native?, do: broadcast(lease)
  end

  defp broadcast(lease) do
    Dawarich.Imports.Events.broadcast(lease.import.user_id)
  rescue
    error -> Logger.warning("Native import progress failed: #{Exception.message(error)}")
  end

  defp altitude_decimal?(lease, context) do
    Map.get_lazy(context, :altitude_decimal?, fn ->
      ImportState.effect!(lease, fn ->
        lease.repo.query!(
          "SELECT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='points' AND column_name='altitude_decimal')",
          [],
          log: false
        ).rows == [[true]]
      end)
    end)
  end

  defp clock(%{now: fun}) when is_function(fun, 0), do: fun.()
  defp clock(%{now: now}), do: now
end
