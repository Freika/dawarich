defmodule Dawarich.Imports.Providers do
  @moduledoc false
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  def request(scope, name, opts) when name in ~w(start_immich_import start_photoprism_import) do
    repo = Dawarich.Imports.NativeReads.repo(opts)

    with {:ok, _} <- Dawarich.Accounts.NativeAccess.admit(scope, repo) do
      repo.transaction(fn ->
        provider =
          String.replace_prefix(name, "start_", "") |> String.replace_suffix("_import", "")

        kind = "imports." <> provider <> "_geodata"

        unless Dawarich.Jobs.Ownership.lock(repo, "command:" <> kind) == :oban,
          do: repo.rollback(:not_owned)

        repo.query!("SELECT id FROM users WHERE id=$1 FOR SHARE", [scope.user.id], log: false)

        current =
          case Dawarich.Accounts.NativeAccess.admit(scope, repo) do
            {:ok, current} -> current
            {:error, reason} -> repo.rollback(reason)
          end

        unless Dawarich.Entitlements.future?(current.user.active_until, DateTime.utc_now()),
          do: repo.rollback(:inactive)

        unless provider in available(repo, current.user.id), do: repo.rollback(:unconfigured)

        case Dawarich.Imports.IntegrationCommands.enqueue(repo, current.user.id, name,
               locale: scope.locale
             ) do
          {:ok, :queued} -> :queued
          {:error, reason} -> repo.rollback(reason)
        end
      end)
    end
  rescue
    _ -> {:error, :enqueue_failed}
  end

  def request(_, _, _), do: {:error, :unknown_job}

  def available(repo, owner) do
    case repo.query!("SELECT settings FROM users WHERE id=$1 AND deleted_at IS NULL", [owner],
           log: false
         ).rows do
      [[settings]] ->
        settings = Dawarich.UserSettings.safe(settings)

        for name <- ~w(immich photoprism),
            Ruby.present?(settings[name <> "_url"]) and
              Ruby.present?(settings[name <> "_api_key"]),
            do: name

      _ ->
        []
    end
  end
end
