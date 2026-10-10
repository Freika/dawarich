defmodule Dawarich.Uploads do
  @moduledoc false
  alias Dawarich.Uploads.{Claims, Records, Reservations, SweepWorker}
  alias Dawarich.Repo

  def target(scope, ref, attrs, opts \\ []),
    do: Dawarich.Uploads.Target.grant(scope, ref, attrs, opts)

  def reserve(scope, entry, policy), do: Reservations.reserve(scope, entry, policy)
  def claim(scope, refs, operation, opts \\ []), do: Claims.claim(scope, refs, operation, opts)
  def sweep(opts \\ []), do: SweepWorker.run(opts)

  def cancel(scope, ref, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    with {:ok, _} <- Dawarich.Accounts.NativeAccess.admit(scope, repo) do
      repo.transaction(fn ->
        current = Records.actor!(repo, scope)
        row = Records.read(repo, ref, current.user.id, true)

        cond do
          is_nil(row) ->
            repo.rollback(:not_found)

          row.state in ["cancelled", "expired", "purged"] ->
            :cancelled

          row.state == "claimed" and row.kind != "rich_text" ->
            repo.rollback(:claimed)

          Records.attached?(repo, row.blob_id) ->
            repo.rollback(:attached)

          not Dawarich.Storage.UploadReceipts.owned?(repo, row.blob_id, current.user.id) ->
            repo.rollback(:not_found)

          true ->
            Records.cancel!(repo, row, "cancelled")
        end
      end)
    end
  end
end
