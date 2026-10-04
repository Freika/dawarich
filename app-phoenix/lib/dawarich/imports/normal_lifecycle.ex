defmodule Dawarich.Imports.NormalLifecycle do
  @moduledoc false
  alias Dawarich.Imports.{
    Adapters,
    ImportMessages,
    ImportState,
    LeaseLost,
    NormalPreparation,
    Postprocessing,
    Tempfiles,
    ZipFanout
  }

  alias Dawarich.Imports.Kml.Kmz
  alias Dawarich.{Notifications, RailsCommands}

  def call(lease, context) do
    if Dawarich.Jobs.Processed.done?(lease.repo, lease.event_id) do
      :ok
    else
      ImportState.with_snapshot(lease, fn state ->
        context = Map.put(context, :fence, fn fun -> ImportState.effect!(lease, fun) end)
        result = if state.mode == :terminal, do: :ok, else: process(lease, state, context)

        case result do
          {:legacy, _} = legacy ->
            legacy

          :removed ->
            :ok

          :ok ->
            finish(lease, context)
            :ok
        end
      end)
    end
  end

  defp process(lease, state, context) do
    Tempfiles.with_files(fn adopt ->
      case NormalPreparation.download(lease, state, context, adopt) do
        {:file, path, filename} ->
          run_import(lease, state, context, path, filename)

        {:archive, path} ->
          run_archive(lease, state, context, path)

        {:legacy, _} = legacy ->
          legacy

        {:error, error, stack} ->
          failure(lease, state.import, context, error, stack)
          ImportState.complete!(lease, clock(context))
          :ok
      end
    end)
  end

  defp run_archive(lease, state, context, path) do
    ImportState.start!(lease, clock(context))
    publish(lease, context)

    case ZipFanout.call(lease, path, context) do
      :removed ->
        :removed

      {:error, error, stack} ->
        failure(lease, state.import, context, error, stack)
        ImportState.complete!(lease, clock(context))
        :ok
    end
  end

  defp run_import(lease, state, context, path, filename) do
    try do
      ImportState.start!(lease, clock(context))
      publish(lease, context)
      source = NormalPreparation.source(lease, path, filename, context)

      case Adapters.fetch(source) do
        {:ok, adapter} ->
          driver =
            context
            |> Map.put(:altitude_decimal?, altitude_decimal?(lease, context))
            |> Map.put(:fail_import, fn message ->
              ImportState.fail!(lease, %ArgumentError{message: message}, clock(context))
            end)

          import = ImportState.import!(lease)

          if source == 9 and String.ends_with?(String.downcase(filename), ".kmz"),
            do: Kmz.with_kml(path, driver, fn leaf -> adapter.call(leaf, import, driver) end),
            else: adapter.call(path, import, driver)

          Postprocessing.call(lease, import, context)
          :ok

        :error ->
          {:legacy, :unsupported_normal_source}
      end
    rescue
      error in LeaseLost -> reraise error, __STACKTRACE__
      error -> failure(lease, state.import, context, error, __STACKTRACE__)
    after
      ImportState.complete!(lease, clock(context))
    end
  end

  defp finish(lease, context) do
    ImportState.effect!(lease, fn ->
      import = ImportState.import!(lease)
      if import.status == 2, do: Postprocessing.enqueue_extraction!(lease.repo, import, context)
      publish(lease, context)
      Map.get(context, :on_terminal, fn -> :ok end).()
    end)

    Dawarich.Imports.Events.broadcast(lease.import.user_id)
  end

  defp failure(lease, import, context, error, stack) do
    ImportState.fail!(lease, error, clock(context))
    publish(lease, context)
    message = ImportMessages.failure(import, context, error, stack)

    ImportState.effect!(lease, fn ->
      Notifications.create!(
        lease.repo,
        import.user_id,
        message.kind,
        message.title,
        message.content,
        DateTime.to_naive(clock(context))
      )
    end)

    if report = Map.get(context, :report_error), do: report.(error, "Import failed")
    :ok
  end

  defp publish(lease, context) do
    ImportState.effect!(lease, fn ->
      RailsCommands.insert!(lease.repo, "imports.progress", %{
        "import_id" => lease.import.id,
        "user_id" => lease.import.user_id,
        "locale" => context.locale
      })
    end)

    Dawarich.Imports.Events.broadcast(lease.import.user_id)
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
