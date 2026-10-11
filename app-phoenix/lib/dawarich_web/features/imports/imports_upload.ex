defmodule DawarichWeb.ImportsUpload do
  @moduledoc false
  use DawarichWeb, :html
  import Phoenix.LiveView
  alias Dawarich.{Imports, Uploads}

  def configure(socket) do
    limits = Uploads.Policy.limits()

    socket
    |> assign(
      checksums: %{},
      upload_refs: %{},
      upload_kind: :imports,
      upload_limits: limits,
      upload_error: nil,
      upload_fallback: false
    )
    |> allow_upload(:files,
      accept: :any,
      max_entries: limits.max_entries,
      max_file_size: limits.max_bytes,
      auto_upload: true,
      external: &DawarichWeb.DirectUpload.presign/2
    )
  end

  def event("validate_files", _, socket), do: {:noreply, assign(socket, upload_error: nil)}

  def event("archive_checksum", %{"ref" => ref, "checksum" => checksum}, socket)
      when is_binary(checksum) do
    refs = Enum.map(socket.assigns.uploads.files.entries, & &1.ref)

    if ref in refs and checksum =~ ~r/\A[A-Za-z0-9+\/]{22}==\z/,
      do:
        {:noreply, update(socket, :checksums, &(&1 |> Map.take(refs) |> Map.put(ref, checksum)))},
      else: {:noreply, socket}
  end

  def event("cancel_upload", %{"ref" => ref}, socket) do
    if Enum.any?(socket.assigns.uploads.files.entries, &(&1.ref == ref)) do
      if owned = socket.assigns.upload_refs[ref],
        do: Uploads.cancel(socket.assigns.current_scope, owned)

      {:noreply,
       socket
       |> cancel_upload(:files, ref)
       |> update(:checksums, &Map.delete(&1, ref))
       |> update(:upload_refs, &Map.delete(&1, ref))}
    else
      {:noreply, socket}
    end
  end

  def event("upload_preparation_error", %{"stage" => stage}, socket)
      when stage in ~w(checksum preparation target upload timeout),
      do: {:noreply, assign(socket, upload_error: "native_upload." <> stage)}

  def event("upload_selection_error", %{"kind" => "too_many_files"}, socket),
    do: {:noreply, assign(socket, upload_error: "native_upload.too_many_files")}

  def event("upload_preparation_fallback", %{"kind" => kind}, socket)
      when kind in ~w(size compression),
      do: {:noreply, assign(socket, upload_fallback: true)}

  def event("start_imports", _, socket) do
    case uploaded_entries(socket, :files) do
      {[_ | _] = entries, []} ->
        refs = Enum.map(entries, &socket.assigns.upload_refs[&1.ref])

        case Imports.create(socket.assigns.current_scope, refs) do
          {:ok, ids} ->
            consume_uploaded_entries(socket, :files, fn _, _ -> {:ok, :claimed} end)

            {:noreply,
             socket
             |> assign(checksums: %{}, upload_refs: %{})
             |> put_flash(
               :notice,
               t(
                 socket.assigns.locale,
                 "controllers.imports.size_files_are_queued_to_be_imported_in_background",
                 %{"size" => length(ids)}
               )
             )
             |> push_navigate(to: "/imports")}

          {:error, reason} ->
            {:noreply, assign(socket, upload_error: error_key(reason))}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def event(_, _, socket), do: {:noreply, socket}

  defp error_key(:file_too_large), do: "javascript.upload.file_size_limit"
  defp error_key(:import_limit), do: "javascript.upload.import_limit"
  defp error_key(_), do: "native_upload.upload"

  def form(assigns) do
    assigns =
      assign(
        assigns,
        :ready,
        assigns.upload.entries != [] and Enum.all?(assigns.upload.entries, & &1.done?) and
          upload_errors(assigns.upload) == []
      )

    ~H"""
    <form
      id="phx-import-upload"
      class="space-y-4 min-w-0"
      phx-hook="ArchiveChecksum"
      data-upload-kind="imports"
      data-upload-name="files"
      data-max-entries={@limits.max_entries}
      data-preparation-bytes={@limits.preparation_bytes}
      data-preparation-original-bytes={@limits.preparation_original_bytes}
      phx-change="validate_files"
      phx-submit="start_imports"
    >
      <label for="import_files" class="block">{t(
        @locale,
        "imports.form.select_one_or_multiple_files",
        %{}
      )}</label>
      <input
        id="import_files"
        type="file"
        multiple
        accept={@accept}
        data-native-selection
        data-testid="import-file-input"
        class="file-input file-input-bordered w-full min-w-0"
      />
      <.live_file_input
        upload={@upload}
        class="hidden"
        aria-label={t(@locale, "imports.form.select_one_or_multiple_files", %{})}
        data-idle-timeout={@limits.idle_timeout}
      />
      <p class="text-sm [overflow-wrap:anywhere]">
        {t(@locale, "imports.form.files_will_be_uploaded_directly_to_storage_please_be_patient", %{})}
      </p>
      <span
        id="import-checksum-progress"
        data-checksum-progress
        phx-update="ignore"
        aria-live="polite"
      ></span>
      <p :if={@fallback} role="status">{t(@locale, "native_upload.raw_fallback", %{})}</p>
      <p :if={@error} role="alert" class="text-error [overflow-wrap:anywhere]">
        {t(@locale, @error, %{"count" => 5})}
      </p>
      <div :for={entry <- @upload.entries} data-entry-ref={entry.ref} class="min-w-0 space-y-1">
        <div class="flex flex-wrap min-w-0 items-center gap-2">
          <span class="min-w-0 flex-1 [overflow-wrap:anywhere]">{(entry.client_meta || %{})[
            "original_filename"
          ] || entry.client_name}</span>
          <span>{entry.progress}%</span>
          <button
            type="button"
            class="btn btn-sm"
            phx-click="cancel_upload"
            phx-value-ref={entry.ref}
            aria-label={t(@locale, "devise.registrations.edit.cancel", %{})}
          >{t(@locale, "devise.registrations.edit.cancel", %{})}</button>
        </div>
        <progress
          class="progress w-full"
          value={entry.progress}
          max="100"
          aria-label={entry.client_name}
        ></progress>
        <p :for={error <- upload_errors(@upload, entry)} role="alert" class="text-error">
          {upload_error(@locale, error)}
        </p>
      </div>
      <p :for={error <- upload_errors(@upload)} role="alert" class="text-error">
        {upload_error(@locale, error)}
      </p>
      <button
        type="submit"
        data-testid="import-submit"
        class="btn btn-primary max-w-full whitespace-normal"
        disabled={!@ready}
        phx-disable-with={t(@locale, "devise.registrations.edit.importing", %{})}
      >{t(@locale, "helpers.submit.create", %{"model" => "Import"})}</button>
    </form>
    """
  end

  defp upload_error(_locale, {:external_metadata_failure, %{reason: reason}}), do: reason
  defp upload_error(locale, :too_large), do: t(locale, "javascript.upload.file_size_limit", %{})
  defp upload_error(locale, :too_many_files), do: t(locale, "native_upload.too_many_files", %{})
  defp upload_error(locale, _), do: t(locale, "native_upload.upload", %{})
end
