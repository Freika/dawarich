defmodule DawarichWeb.DirectUpload do
  @moduledoc false

  alias Dawarich.{RailsMessages, Storage, UserData}
  alias Dawarich.Storage.Blobs
  alias DawarichWeb.{ActiveStorageUrls, Translate}

  @legacy_trial_bytes 11 * 1024 * 1024

  def presign(entry, socket) do
    %{current_user: user, locale: locale, base_url: base_url, checksums: checksums} =
      socket.assigns

    checksum = checksums[entry.ref]

    cond do
      not (is_binary(checksum) and checksum != "") ->
        refuse(
          socket,
          locale,
          "controllers.settings.users.an_error_occurred_while_starting_the_import_please_try_again"
        )

      not UserData.zip?(%{content_type: entry.client_type, filename: entry.client_name}) ->
        refuse(socket, locale, "javascript.messages.please_select_a_valid_zip_file")

      legacy_trial?(user) and entry.client_size > @legacy_trial_bytes ->
        refuse(socket, locale, "javascript.upload.file_size_limit")

      true ->
        now = DateTime.utc_now()
        storage = Storage.services!(System.get_env())
        service = Storage.service!(storage, storage.default)

        {:ok, blob} =
          Blobs.create_before_direct_upload(
            service,
            %{
              "filename" => entry.client_name,
              "byte_size" => entry.client_size,
              "checksum" => checksum,
              "content_type" => entry.client_type,
              "metadata" => nil
            },
            DateTime.to_naive(now),
            user_id: user.id
          )

        {url, headers} = ActiveStorageUrls.direct_upload(service, blob, base_url, now)

        {:ok,
         %{
           uploader: "Direct",
           url: url,
           headers: Map.new(headers),
           signed_id: RailsMessages.blob_id(blob.id)
         }, socket}
    end
  end

  defp legacy_trial?(user), do: user.status == 2 and user.subscription_source in [nil, 0]

  defp refuse(socket, locale, key), do: {:error, %{reason: Translate.t(locale, key, %{})}, socket}
end
