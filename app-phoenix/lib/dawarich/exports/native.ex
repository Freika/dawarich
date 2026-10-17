defmodule Dawarich.Exports.Native do
  @moduledoc false
  alias Dawarich.Accounts.NativeAccess

  def page(scope, list, opts) do
    repo = repo(opts)

    with {:ok, current} <- NativeAccess.admit(scope, repo) do
      {:ok, Dawarich.ImportExportIndex.exports(current.user, list, repo)}
    end
  end

  def subscribe(scope, opts) do
    with {:ok, current} <- NativeAccess.admit(scope, repo(opts)),
         do: Dawarich.Exports.Events.subscribe(current.user.id)
  end

  def request(scope, {:points, export, receipt}, opts) do
    repo = repo(opts)

    with {:ok, receipt} <- Ecto.UUID.cast(receipt),
         true <- export.file_format in [0, 1],
         {:ok, _} <- NativeAccess.admit(scope, repo) do
      write(repo, scope, fn current ->
        key = "native-points-export:#{current.user.id}:#{receipt}"

        case repo.query!(
               "SELECT aggregate_id FROM public.job_outbox WHERE command_type='exports.points' AND dedupe_key=$1",
               [key],
               log: false
             ).rows do
          [[id]] ->
            id

          [] ->
            id = create!(repo, current, export)

            repo.query!(
              "UPDATE public.job_outbox SET dedupe_key=$1 WHERE command_type='exports.points' AND aggregate_id=$2",
              [key, id],
              log: false
            )

            id
        end
      end)
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_submission}
    end
  end

  def request(scope, {:trip, id, format}, opts) do
    repo = repo(opts)

    with {:ok, _} <- NativeAccess.admit(scope, repo) do
      write(repo, scope, fn current ->
        case Dawarich.Trips.WebExport.prepare(repo, current.user, id, format, %{}) do
          {:ok, export} -> create!(repo, current, export)
          {:invalid, :format} -> repo.rollback(:invalid_format)
          {:error, reason} -> repo.rollback(reason)
          _ -> repo.rollback(:unavailable)
        end
      end)
    end
  end

  def request(scope, params, opts) do
    repo = repo(opts)

    with {:ok, _} <- NativeAccess.admit(scope, repo),
         {:ok, export} <- Dawarich.Exports.parse_submission(params) do
      write(repo, scope, fn current ->
        create!(repo, current, export)
      end)
    end
  end

  def delete(scope, id, opts) do
    repo = repo(opts)

    with {:ok, _} <- NativeAccess.admit(scope, repo) do
      write(repo, scope, fn current ->
        case Dawarich.Exports.Delete.call(repo, current.user.id, id, native: true) do
          {:ok, result} -> result
          {:error, reason} -> repo.rollback(reason)
        end
      end)
    end
  end

  defp create!(repo, current, export) do
    unless Dawarich.Imports.NativeOwnership.lock(repo, "command:exports.points") == :oban,
      do: repo.rollback(:not_owned)

    case Dawarich.PointExports.create(export, current.user, current.locale, repo) do
      {:ok, id} -> id
      {:error, _} -> repo.rollback(:unavailable)
    end
  end

  defp write(repo, scope, effect) do
    repo.transaction(fn ->
      repo.query!("SELECT id FROM users WHERE id=$1 FOR UPDATE", [scope.user.id], log: false)

      case NativeAccess.admit(scope, repo) do
        {:ok, current} ->
          effect.(current)

        {:error, reason} ->
          repo.rollback(reason)
      end
    end)
  end

  defp repo(opts), do: Keyword.get(opts, :repo, Dawarich.Repo)
end
