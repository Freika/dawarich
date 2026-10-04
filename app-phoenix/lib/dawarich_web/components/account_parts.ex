defmodule DawarichWeb.AccountParts do
  @moduledoc false
  use DawarichWeb, :html

  attr :locale, :string, required: true
  attr :user, :map, required: true
  attr :oauth, :string, default: nil
  attr :rails_csrf_token, :string, default: nil
  attr :errors, :list, default: []
  attr :submitted_email, :string, default: nil

  def profile(assigns), do: DawarichWeb.AccountProfile.profile(assigns)

  attr :locale, :string, required: true
  attr :upload_url, :string, required: true
  attr :legacy_trial, :boolean, required: true
  attr :rails_csrf_token, :string, default: nil

  def import_dialog(assigns) do
    ~H"""
    <dialog id="import_modal" class="modal" phx-hook="RailsStimulus" phx-update="ignore">
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
          class="space-y-4"
          data-turbo="false"
          data-controller="upload"
          data-upload-url-value={@upload_url}
          data-upload-field-name-value="archive"
          data-upload-multiple-value="false"
          data-upload-validate-zip-value="true"
          data-upload-user-trial-value={to_string(@legacy_trial)}
          data-upload-target="form"
          enctype="multipart/form-data"
          action="/settings/users/import"
          accept-charset="UTF-8"
          method="post"
        >
          <input
            :if={@rails_csrf_token}
            type="hidden"
            name="authenticity_token"
            value={@rails_csrf_token}
          />
          <div class="form-control">
            <label class="label" for="archive"><span class="label-text">{t(
              @locale,
              "devise.registrations.edit.select_zip_archive",
              %{}
            )}</span></label>
            <input
              accept=".zip"
              required="required"
              class="file-input file-input-bordered w-full"
              data-upload-target="input"
              data-direct-upload-url={@upload_url}
              type="file"
              name="archive"
              id="archive"
            />
            <div class="mt-2 text-sm text-base-content/60">
              {t(
                @locale,
                "devise.registrations.edit.file_will_be_uploaded_directly_to_storage_please_be_patient",
                %{}
              )}
            </div>
          </div>
          <div class="modal-action flex-col-reverse sm:flex-row">
            <button type="button" class="btn w-full sm:w-auto" onclick="import_modal.close()">{t(
              @locale,
              "devise.registrations.edit.cancel",
              %{}
            )}</button>
            <input
              type="submit"
              name="commit"
              value={t(@locale, "devise.registrations.edit.import_data", %{})}
              class="btn btn-primary w-full sm:w-auto"
              data-disable-with={t(@locale, "devise.registrations.edit.importing", %{})}
              data-upload-target="submit"
            />
          </div>
        </form>
      </div>
      <form method="dialog" class="modal-backdrop">
        <button>{t(@locale, "devise.registrations.edit.close", %{})}</button>
      </form>
    </dialog>
    """
  end

  attr :locale, :string, required: true
  attr :self_hosted, :boolean, required: true
  attr :trial, :boolean, required: true
  attr :trial_at, :map, default: nil
  attr :auto_converting, :boolean, required: true
  attr :manager, :string, default: nil
  attr :subscription, :string, default: nil
  attr :points, :integer, required: true

  def plan_cards(assigns), do: DawarichWeb.PlanCards.plan_cards(assigns)

  attr :locale, :string, required: true
  attr :user, :map, required: true
  attr :self_hosted, :boolean, required: true
  attr :oauth, :string, default: nil
  attr :rails_csrf_token, :string, default: nil

  def data_tools(assigns), do: DawarichWeb.DangerZone.data_tools(assigns)
end
