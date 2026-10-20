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
    assigns = assigns |> Map.put_new(:variant, :page) |> Map.put_new(:target, nil)
    assigns = assign(assigns, onboarding: assigns.variant == :onboarding)

    assigns =
      assign(
        assigns,
        :ready,
        assigns.upload.entries != [] and Enum.all?(assigns.upload.entries, & &1.done?) and
          upload_errors(assigns.upload) == []
      )

    ~H"""
    <form
      id={if @onboarding, do: "native-onboarding-upload", else: "phx-import-upload"}
      class="contents"
      method="post"
      action="/imports"
      enctype="multipart/form-data"
      accept-charset="UTF-8"
      phx-target={@target}
      phx-hook="ArchiveChecksum"
      data-upload-kind="imports"
      data-upload-name="files"
      data-max-entries={@limits.max_entries}
      data-preparation-bytes={@limits.preparation_bytes}
      data-preparation-original-bytes={@limits.preparation_original_bytes}
      phx-change="validate_files"
      phx-submit="start_imports"
    >
      <input type="hidden" name="authenticity_token" value="" />
      <label class={
        if @onboarding, do: "form-control w-full mb-4", else: "form-control w-full max-w-xs my-5"
      }>
        <div class="label">
          <span class="label-text">{t(
            @locale,
            if(@onboarding,
              do: "map.onboarding_modal.select_one_or_multiple_files",
              else: "imports.form.select_one_or_multiple_files"
            ),
            %{}
          )}</span>
        </div>
        <input type="hidden" name="import[files][]" value="" />
        <.selection onboarding={@onboarding} accept={if @onboarding, do: nil, else: @accept} />
        <div class={
          if @onboarding, do: "text-xs text-base-content/60 mt-2", else: "text-sm text-gray-500 mt-2"
        }>
          {t(
            @locale,
            if(@onboarding,
              do: "map.onboarding_modal.files_will_be_uploaded_directly_to_storage_please_be_patient",
              else: "imports.form.files_will_be_uploaded_directly_to_storage_please_be_patient"
            ),
            %{}
          )}
        </div>
      </label>
      <.live_file_input
        upload={@upload}
        data-native-upload-transport
        class="hidden"
        aria-label={t(@locale, "imports.form.select_one_or_multiple_files", %{})}
        data-idle-timeout={@limits.idle_timeout}
      />
      <span
        id={
          if @onboarding, do: "native-onboarding-checksum-progress", else: "import-checksum-progress"
        }
        data-checksum-progress
        phx-update="ignore"
        class={@onboarding && @upload.entries == [] && "hidden"}
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
            phx-target={@target}
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
      <div class={if @onboarding, do: "flex justify-end", else: "inline"}>
        <input
          type="submit"
          name="commit"
          value={
            if @onboarding,
              do: t(@locale, "map.onboarding_modal.import_files", %{}),
              else: t(@locale, "helpers.submit.create", %{"model" => "Import"})
          }
          class="btn btn-primary"
          data-testid={if @onboarding, do: "onboarding-import-submit", else: "import-submit"}
          disabled={!@ready}
          phx-disable-with={t(@locale, "devise.registrations.edit.importing", %{})}
        />
      </div>
    </form>
    """
  end

  defp selection(assigns) do
    ~H"""
    <input
      id={if @onboarding, do: "files", else: "import_files"}
      type="file"
      name="import[files][]"
      multiple="multiple"
      accept={assigns[:accept]}
      data-native-selection
      data-testid={if @onboarding, do: "onboarding-import-file-input", else: "import-file-input"}
      class={
        if @onboarding,
          do: "file-input file-input-bordered w-full",
          else: "file-input file-input-bordered w-full max-w-xs"
      }
    />
    """
  end

  defp upload_error(_locale, {:external_metadata_failure, %{reason: reason}}), do: reason
  defp upload_error(locale, :too_large), do: t(locale, "javascript.upload.file_size_limit", %{})
  defp upload_error(locale, :too_many_files), do: t(locale, "native_upload.too_many_files", %{})
  defp upload_error(locale, _), do: t(locale, "native_upload.upload", %{})
end
