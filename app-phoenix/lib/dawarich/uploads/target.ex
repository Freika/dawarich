defmodule Dawarich.Uploads.Target do
  @moduledoc false
  alias Dawarich.Uploads.Records
  alias Dawarich.{Repo, Storage}

  def grant(scope, ref, attrs, opts) do
    repo = Keyword.get(opts, :repo, Repo)

    with true <- attrs == %{},
         {:ok, _} <- Dawarich.Accounts.NativeAccess.admit(scope, repo) do
      repo.transaction(fn ->
        current = Records.actor!(repo, scope)

        row = Records.read(repo, ref, current.user.id, true) |> then(&Records.pending!(repo, &1))

        unless row.kind == "rich_text" or
                 Dawarich.Entitlements.future?(current.user.active_until, DateTime.utc_now()),
               do: repo.rollback(:inactive)

        blob = Storage.Blobs.find(row.blob_id, repo)

        {:ok, storage} =
          Storage.ImportServices.resolve(
            Keyword.get_lazy(opts, :services, &Dawarich.Imports.StorageContext.services/0),
            blob
          )

        issued = Keyword.get(opts, :clock, &DateTime.utc_now/0).()
        expires = issued |> DateTime.add(300) |> DateTime.to_naive()

        until =
          if row.target_until && NaiveDateTime.compare(row.target_until, expires) == :gt,
            do: row.target_until,
            else: expires

        repo.query!(
          "UPDATE phoenix.native_uploads SET target_until=$2 WHERE reference=$1",
          [ref, until],
          log: false
        )

        %{blob: blob, storage: storage, issued_at: issued}
      end)
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_input}
    end
  end
end
