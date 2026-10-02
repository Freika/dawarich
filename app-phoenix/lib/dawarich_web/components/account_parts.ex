defmodule DawarichWeb.AccountParts do
  @moduledoc false
  use DawarichWeb, :html

  @minimum_password_length 12

  attr :locale, :string, required: true
  attr :user, :map, required: true
  attr :oauth, :string, default: nil
  attr :rails_csrf_token, :string, default: nil

  def profile(assigns) do
    assigns = assign(assigns, :minimum, @minimum_password_length)

    ~H"""
    <div class="card bg-base-100 shadow-xl">
      <div class="card-body gap-5 p-5 sm:p-6">
        <div>
          <h2 class="card-title text-2xl">{t(@locale, "devise.registrations.edit.profile", %{})}</h2>
          <p class="mt-1 text-sm text-base-content/70">
            {t(
              @locale,
              "devise.registrations.edit.update_your_email_address_and_password_from_one_place",
              %{}
            )}
          </p>
        </div>
        <div
          :if={@oauth}
          class="rounded-xl border border-base-300 bg-base-200/50 px-4 py-3 text-sm font-medium"
        >
          {t(@locale, "devise.registrations.edit.connected_with", %{})} {@oauth}
        </div>
        <form
          class="edit_user"
          id="edit_user"
          phx-update="ignore"
          data-turbo-method="put"
          data-turbo="false"
          action="/users"
          accept-charset="UTF-8"
          method="post"
        >
          <input type="hidden" name="_method" value="put" /><input
            :if={@rails_csrf_token}
            type="hidden"
            name="authenticity_token"
            value={@rails_csrf_token}
          />
          <div class="form-control">
            <label class="label" for="user_email"><span class="label-text">{t(
              @locale,
              "devise.registrations.edit.email",
              %{}
            )}</span></label>
            <input
              autofocus="autofocus"
              autocomplete="email"
              class="input input-bordered w-full"
              type="email"
              value={@user.email}
              name="user[email]"
              id="user_email"
            />
          </div>
          <div class="form-control mt-5">
            <label class="label" for="user_password"><span class="label-text">{t(
              @locale,
              "devise.registrations.edit.new_password",
              %{}
            )}
            <span class="text-base-content/60">{t(
              @locale,
              "devise.registrations.edit.leave_blank_to_keep_the_current_one",
              %{}
            )}</span></span></label>
            <em class="text-xs text-base-content/60">({@minimum} {t(
              @locale,
              "devise.registrations.edit.characters_minimum",
              %{}
            )}</em>
            <input
              autocomplete="new-password"
              class="input input-bordered w-full"
              type="password"
              name="user[password]"
              id="user_password"
            />
          </div>
          <div class="form-control mt-5">
            <label class="label" for="user_password_confirmation"><span class="label-text">{t(
              @locale,
              "devise.registrations.edit.password_confirmation",
              %{}
            )}</span></label>
            <em class="text-xs text-base-content/60">({@minimum} {t(
              @locale,
              "devise.registrations.edit.characters_minimum",
              %{}
            )}</em>
            <input
              autocomplete="new-password"
              class="input input-bordered w-full"
              type="password"
              name="user[password_confirmation]"
              id="user_password_confirmation"
            />
          </div>
          <div :if={!@oauth} class="form-control mt-5">
            <label class="label" for="user_current_password"><span class="label-text">{t(
              @locale,
              "devise.registrations.edit.current_password",
              %{}
            )}</span></label>
            <i class="text-xs text-base-content/60">{t(
              @locale,
              "devise.registrations.edit.required_to_confirm_your_changes",
              %{}
            )}</i>
            <input
              autocomplete="current-password"
              class="input input-bordered mt-2 w-full"
              type="password"
              name="user[current_password]"
              id="user_current_password"
            />
          </div>
          <div class="form-control mt-6">
            <input
              type="submit"
              name="commit"
              value={t(@locale, "devise.registrations.edit.save_changes", %{})}
              class="btn btn-primary w-full sm:w-auto"
              data-disable-with={t(@locale, "devise.registrations.edit.save_changes", %{})}
            />
          </div>
        </form>
        <div class="mt-5 space-y-2 text-sm">
          <div>
            <a class="link link-hover text-base-content/70" href="/users/unlock/new">{t(
              @locale,
              "devise.shared.links.didn_t_receive_unlock_instructions",
              %{}
            )}</a>
          </div>
        </div>
      </div>
    </div>
    """
  end

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
