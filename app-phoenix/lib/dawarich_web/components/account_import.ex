defmodule DawarichWeb.AccountImport do
  @moduledoc false
  use DawarichWeb, :html

  def dialog(assigns) do
    assigns =
      assign(
        assigns,
        :can_import,
        Enum.any?(assigns.upload.entries, &Map.has_key?(assigns.checksums, &1.ref))
      )

    ~H"""
    <dialog id="import_modal" class="modal">
      <div class="modal-box">
        <h3 class="mb-4 text-lg font-bold">
          {t(@locale, "devise.registrations.edit.import_your_data", %{})}
        </h3>
        <p class="mb-4 text-sm text-base-content/70">
          {t(
            @locale,
            "devise.registrations.edit.upload_a_zip_file_containing_your_exported_dawarich_data_to",
            %{}
          )}
        </p>
        <form
          id="import-form"
          class="space-y-4"
          phx-hook="ArchiveChecksum"
          phx-change="validate_archive"
          phx-submit="import_archive"
        >
          <div class="form-control">
            <label class="label" for={@upload.ref}>
              <span class="label-text">
                {t(@locale, "devise.registrations.edit.select_zip_archive", %{})}
              </span>
            </label>
            <.live_file_input upload={@upload} class="file-input file-input-bordered w-full" />
            <div class="mt-2 text-sm text-base-content/60">
              {t(
                @locale,
                "devise.registrations.edit.file_will_be_uploaded_directly_to_storage_please_be_patient",
                %{}
              )}
              <span data-checksum-progress phx-update="ignore" id="import-checksum-progress"></span>
            </div>
          </div>
          <div :for={entry <- @upload.entries} class="space-y-1" data-entry-ref={entry.ref}>
            <div class="flex items-center gap-2 text-sm">
              <span class="min-w-0 flex-1 truncate [overflow-wrap:anywhere]">{entry.client_name}</span>
              <span>{entry.progress}%</span>
              <button
                type="button"
                class="btn btn-ghost btn-xs"
                phx-click="cancel_archive"
                phx-value-ref={entry.ref}
                aria-label={t(@locale, "devise.registrations.edit.cancel", %{})}
              >
                ✕
              </button>
            </div>
            <progress class="progress progress-primary w-full" value={entry.progress} max="100"></progress>
            <p :for={error <- upload_errors(@upload, entry)} class="text-sm text-error">
              {error_text(@locale, error)}
            </p>
          </div>
          <p :for={error <- upload_errors(@upload)} class="text-sm text-error">
            {error_text(@locale, error)}
          </p>
          <div class="modal-action flex-col-reverse sm:flex-row">
            <button type="button" class="btn w-full sm:w-auto" onclick="import_modal.close()">
              {t(@locale, "devise.registrations.edit.cancel", %{})}
            </button>
            <button
              type="submit"
              class="btn btn-primary w-full sm:w-auto"
              disabled={not @can_import}
              phx-disable-with={t(@locale, "devise.registrations.edit.importing", %{})}
            >
              {t(@locale, "devise.registrations.edit.import_data", %{})}
            </button>
          </div>
        </form>
      </div>
      <form method="dialog" class="modal-backdrop">
        <button>{t(@locale, "devise.registrations.edit.close", %{})}</button>
      </form>
    </dialog>
    """
  end

  defp error_text(_locale, {:external_metadata_failure, %{reason: reason}})
       when is_binary(reason),
       do: reason

  defp error_text(_locale, %{reason: reason}) when is_binary(reason), do: reason

  defp error_text(locale, :not_accepted),
    do: t(locale, "javascript.messages.please_select_a_valid_zip_file", %{})

  defp error_text(locale, _error),
    do:
      t(
        locale,
        "controllers.settings.users.an_error_occurred_while_starting_the_import_please_try_again",
        %{}
      )
end
