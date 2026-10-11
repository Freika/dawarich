defmodule Dawarich.Uploads.Claims do
  @moduledoc false
  alias Dawarich.Uploads.Records
  alias Dawarich.{Repo, Storage}

  def claim(scope, refs, operation, opts) do
    repo = Keyword.get(opts, :repo, Repo)

    with {:ok, current} <- Dawarich.Accounts.NativeAccess.admit(scope, repo),
         true <-
           operation in [:imports, :account, :rich_text, :route_video] and is_list(refs) and
             length(refs) in 1..Dawarich.Uploads.Policy.limits().max_entries and
             (operation == :imports or length(refs) == 1) and
             length(Enum.uniq(refs)) == length(refs),
         {:ok, verified} <- verify(repo, current.user.id, refs, opts) do
      repo.transaction(fn ->
        if fun = opts[:before_lock], do: fun.(repo)
        current = Records.actor!(repo, scope)

        unless operation == :rich_text or
                 Dawarich.Entitlements.future?(current.user.active_until, DateTime.utc_now()),
               do: repo.rollback(:inactive)

        for item <- Enum.sort_by(verified, & &1.reference) do
          row =
            Records.read(repo, item.reference, current.user.id, true)
            |> then(&Records.pending!(repo, &1))

          if row.kind != Atom.to_string(operation), do: repo.rollback(:invalid_input)

          if operation in [:imports, :account] and current.user.status == 2 and
               current.user.subscription_source in [nil, 0] and
               (item.blob.byte_size > 11 * 1024 * 1024 or row.original_size > 11 * 1024 * 1024),
             do: repo.rollback(:file_too_large)
        end

        if fun = opts[:after_lock], do: fun.()

        result =
          case opts[:consume] do
            nil -> verified
            consume -> consume.(repo, verified)
          end

        for item <- verified, do: Records.finish!(repo, item, "claimed")
        result
      end)
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_input}
    end
  end

  defp verify(repo, user, refs, opts) do
    Enum.reduce_while(refs, {:ok, []}, fn ref, {:ok, result} ->
      row = Records.read(repo, ref, user)

      case verify_one(repo, row, opts) do
        {:ok, item} -> {:cont, {:ok, result ++ [item]}}
        error -> {:halt, error}
      end
    end)
  end

  defp verify_one(_repo, nil, _opts), do: {:error, :not_found}

  defp verify_one(repo, row, opts) do
    cond do
      row.state != "pending" -> {:error, state(row.state)}
      NaiveDateTime.compare(row.expires_at, NaiveDateTime.utc_now()) != :gt -> {:error, :expired}
      Records.attached?(repo, row.blob_id) -> {:error, :attached}
      true -> verify_object(repo, row, opts)
    end
  end

  defp verify_object(repo, row, opts) do
    with blob when not is_nil(blob) <- Storage.Blobs.find(row.blob_id, repo),
         true <- Storage.UploadReceipts.owned?(repo, blob.id, row.user_id) do
      services = Keyword.get_lazy(opts, :services, &Dawarich.Imports.StorageContext.services/0)
      {:ok, service} = Storage.ImportServices.resolve(services, blob)

      Dawarich.Imports.Tempfiles.with_files(fn adopt ->
        Storage.Reader.download!(service, blob, on_verified: adopt)
        {:ok, Map.put(row, :blob, blob)}
      end)
    else
      _ -> {:error, :not_found}
    end
  rescue
    _ -> {:error, :invalid_object}
  end

  defp state("claimed"), do: :claimed
  defp state("cancelled"), do: :cancelled
  defp state("expired"), do: :expired
  defp state("purged"), do: :purged
end
