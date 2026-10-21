defmodule Dawarich.Imports.UploadCreate do
  @moduledoc false
  alias Dawarich.Imports.{UploadAdmission, UploadRecords}
  alias Dawarich.Imports.NativeOwnership, as: Ownership

  def create(repo, user, files, context) when is_list(files),
    do: files |> Enum.reject(&(&1 == "")) |> create_present(repo, user, context)

  def create(_, _, _, _), do: {:error, :no_files}

  defp create_present([], _repo, _user, _context), do: {:error, :no_files}

  defp create_present(files, repo, user, context) do
    with {:ok, blobs} <-
           UploadAdmission.prepare(repo, files, Map.put(context, :upload_user_id, user.id)) do
      repo.transaction(fn ->
        owners =
          blobs
          |> Enum.map(&command/1)
          |> Enum.uniq()
          |> Enum.sort()
          |> Map.new(&{&1, Ownership.lock(repo, "command:" <> &1)})

        current = UploadAdmission.user!(repo, user.id)
        UploadAdmission.admission!(repo, current, length(blobs), context)
        Enum.map(blobs, &UploadRecords.insert!(repo, current, &1, owners[command(&1)]))
      end)
    end
  end

  defp command(%{source: 8}), do: "users.import_data"
  defp command(%{source: 4}), do: "imports.process_gpx"
  defp command(_), do: "imports.process_normal"
end
