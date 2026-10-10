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

  def request(scope, params, opts) do
    repo = repo(opts)

    with {:ok, _} <- NativeAccess.admit(scope, repo),
         {:ok, export} <- Dawarich.Exports.parse_submission(params) do
      write(repo, scope, fn current ->
        unless Dawarich.Imports.NativeOwnership.lock(repo, "command:exports.points") == :oban,
          do: repo.rollback(:not_owned)

        case Dawarich.PointExports.create(export, current.user, current.locale, repo) do
          {:ok, id} -> id
          {:error, _} -> repo.rollback(:unavailable)
        end
      end)
    end
  end

  def delete(scope, id, opts) do
    repo = repo(opts)

    with {:ok, _} <- NativeAccess.admit(scope, repo) do
      write(repo, scope, fn current ->
        case Dawarich.Exports.Delete.call(repo, current.user.id, id) do
          {:ok, result} -> result
          {:error, reason} -> repo.rollback(reason)
        end
      end)
    end
  end

  defp write(repo, scope, effect) do
    repo.transaction(fn ->
      repo.query!("SELECT id FROM users WHERE id=$1 FOR SHARE", [scope.user.id], log: false)

      case NativeAccess.admit(scope, repo) do
        {:ok, current} ->
          unless Dawarich.Entitlements.future?(current.user.active_until, DateTime.utc_now()),
            do: repo.rollback(:inactive)

          effect.(current)

        {:error, reason} ->
          repo.rollback(reason)
      end
    end)
  end

  defp repo(opts), do: Keyword.get(opts, :repo, Dawarich.Repo)
end
