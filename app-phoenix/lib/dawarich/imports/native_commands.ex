defmodule Dawarich.Imports.NativeCommands do
  @moduledoc false
  alias Dawarich.Imports.{NativeReads, UiRecords, UploadAdmission, UploadRecords, Events}
  alias Dawarich.Uploads.Records

  def create(scope, refs, opts) do
    repo = NativeReads.repo(opts)

    with {:ok, current} <- Dawarich.Accounts.NativeAccess.admit(scope, repo),
         true <- is_list(refs) and length(refs) in 1..Dawarich.Uploads.Policy.limits().max_entries,
         context = NativeReads.context(current.user, repo, opts),
         {:ok, items} <- UploadAdmission.prepare_owned(repo, current.user.id, refs, context) do
      commands = items |> Enum.map(&command/1) |> Enum.uniq() |> Enum.sort()
      opts = Keyword.put(opts, :repo, repo)
      opts = Keyword.put(opts, :before_lock, fn repo -> lock_commands(repo, commands) end)

      opts =
        Keyword.put(opts, :consume, fn repo, verified ->
          current = Records.actor!(repo, scope)
          user = UploadAdmission.user!(repo, current.user.id)
          UploadAdmission.admission!(repo, user, length(verified), context)
          ids = Enum.map(items, &UploadRecords.insert!(repo, user, &1, :oban))
          Events.enqueue(repo, user.id, Ecto.UUID.generate(), :created)
          ids
        end)

      Dawarich.Uploads.claim(scope, refs, :imports, opts)
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_input}
    end
  end

  def change(scope, id, action, attrs, opts) when is_map(attrs) do
    repo = NativeReads.repo(opts)

    with {:ok, _} <- Dawarich.Accounts.NativeAccess.admit(scope, repo) do
      repo.transaction(fn ->
        lock_commands(repo, commands(action))
        current = actor!(repo, scope)

        unless Dawarich.Entitlements.future?(current.user.active_until, DateTime.utc_now()),
          do: repo.rollback(:inactive)

        {:ok, record} = result!(repo, UiRecords.get(repo, current.user.id, id))
        result!(repo, NativeReads.supported(record))
        context = NativeReads.context(current.user, repo, opts)

        case action do
          :update ->
            result!(repo, UiRecords.update(repo, current.user.id, record.id, attrs))

          :delete ->
            result!(
              repo,
              Dawarich.Imports.Destroy.enqueue(repo, current.user.id, record.id, context)
            )

          :extract ->
            result!(repo, UiRecords.extract(repo, current.user.id, record.id, attrs, context))

          :remove ->
            result!(repo, UiRecords.remove_extraction(repo, current.user.id, record.id, context))
        end
        |> then(fn {:ok, value} -> value end)
      end)
    end
  end

  def change(_, _, _, _, _), do: {:error, :invalid_input}

  defp actor!(repo, scope) do
    repo.query!("SELECT id FROM users WHERE id=$1 FOR SHARE", [scope.user.id], log: false)

    case Dawarich.Accounts.NativeAccess.admit(scope, repo) do
      {:ok, current} -> current
      {:error, reason} -> repo.rollback(reason)
    end
  end

  defp result!(repo, {:error, reason}), do: repo.rollback(reason)
  defp result!(_repo, result), do: result

  defp lock_commands(repo, commands) do
    Enum.each(commands, fn command ->
      unless Dawarich.Imports.NativeOwnership.lock(repo, "command:" <> command) == :oban,
        do: repo.rollback(:not_owned)
    end)
  end

  defp commands(:delete), do: ["imports.destroy"]
  defp commands(:extract), do: ["enhanced_import.extract_gpx"]
  defp commands(:remove), do: ["enhanced_import.destroy_gpx"]
  defp commands(:update), do: []
  defp command(%{source: 8}), do: "users.import_data"
  defp command(%{source: 4}), do: "imports.process_gpx"
  defp command(_), do: "imports.process_normal"
end
