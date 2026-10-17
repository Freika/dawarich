defmodule DawarichWeb.DirectUpload do
  @moduledoc false
  alias Dawarich.{Uploads, UserData}
  alias Dawarich.Accounts.Scope
  alias DawarichWeb.Translate

  def presign(entry, socket) do
    %{current_user: user, locale: locale, checksums: checksums} = socket.assigns

    attrs = %{
      filename: entry.client_name,
      byte_size: entry.client_size,
      checksum: checksums[entry.ref] || (entry.client_meta || %{})["checksum"],
      content_type: entry.client_type
    }

    kind = Map.get(socket.assigns, :upload_kind, :account)
    prepared = Map.get(socket.assigns, :prepared_uploads, %{})[entry.ref] || %{}

    original =
      Map.take(entry.client_meta || %{}, ~w(original_filename original_size client_wrapped))

    original = Map.new(original, fn {key, value} -> {String.to_existing_atom(key), value} end)
    attrs = attrs |> Map.merge(original) |> Map.merge(prepared)

    result =
      if kind == :account and not UserData.zip?(attrs),
        do: {:error, :invalid_zip},
        else: Uploads.reserve(Scope.for_user(user, locale), attrs, %{kind: kind})

    case result do
      {:ok, ref} ->
        refs = Map.get(socket.assigns, :upload_refs, %{}) |> Map.put(entry.ref, ref)

        {:ok, %{uploader: "Direct", upload_ref: ref},
         Phoenix.Component.assign(socket, :upload_refs, refs)}

      {:error, reason} ->
        key =
          case reason do
            :invalid_zip ->
              "javascript.messages.please_select_a_valid_zip_file"

            :file_too_large ->
              "javascript.upload.file_size_limit"

            _ ->
              "controllers.settings.users.an_error_occurred_while_starting_the_import_please_try_again"
          end

        {:error, %{reason: Translate.t(locale, key, %{})}, socket}
    end
  end
end
