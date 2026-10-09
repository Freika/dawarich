defmodule DawarichWeb.DangerZone do
  @moduledoc false
  use DawarichWeb, :html
  alias Phoenix.LiveView.JS

  attr :locale, :string, required: true
  attr :user, :map, required: true
  attr :self_hosted, :boolean, required: true
  attr :oauth, :string, default: nil
  attr :rails_csrf_token, :string, default: nil

  def data_tools(assigns) do
    assigns =
      assign(
        assigns,
        :submit,
        t(
          assigns.locale,
          "devise.registrations.edit." <>
            if(assigns.self_hosted,
              do: "delete_my_account",
              else: "email_me_the_confirmation_link"
            ),
          %{}
        )
      )

    ~H"""
    <div class="card bg-base-100 shadow-xl">
      <div class="card-body gap-5 p-5 sm:p-6">
        <div>
          <h2 class="card-title text-2xl">
            {t(@locale, "devise.registrations.edit.data_tools", %{})}
          </h2>
          <p class="mt-1 text-sm text-base-content/70">
            {t(
              @locale,
              "devise.registrations.edit.export_a_backup_or_restore_a_previous_archive",
              %{}
            )}
          </p>
        </div>
        <div class="flex flex-col gap-3 sm:flex-row sm:flex-wrap">
          <button
            id="export-data"
            type="button"
            class="btn btn-primary w-full sm:w-auto"
            phx-click="export_data"
            phx-disable-with={t(@locale, "devise.registrations.edit.export_my_data", %{})}
            data-confirm={
              t(@locale, "devise.registrations.edit.are_you_sure_you_want_to_export_your_data", %{})
            }
          >
            {t(@locale, "devise.registrations.edit.export_my_data", %{})}
          </button>
          <button
            type="button"
            class="btn btn-outline w-full sm:w-auto"
            phx-click={JS.dispatch("dawarich:open-dialog", to: "#import_modal")}
          >{t(@locale, "devise.registrations.edit.import_my_data", %{})}</button>
        </div>
        <div class="rounded-2xl border border-error/30 bg-error/5 p-4">
          <h3 class="text-lg font-semibold">
            {t(@locale, "devise.registrations.edit.danger_zone", %{})}
          </h3>
          <p class="mt-2 text-sm text-base-content/70">
            {t(
              @locale,
              "devise.registrations.edit.deleting_your_account_is_permanent_and_removes_all_your_data",
              %{}
            )}
          </p>
          <div class="mt-4">
            <button
              type="button"
              class="btn btn-error btn-outline w-full sm:w-auto"
              phx-click={JS.dispatch("dawarich:open-dialog", to: "#delete_account_modal")}
            >{t(@locale, "devise.registrations.edit.cancel_my_account", %{})}</button>
          </div>
        </div>
        <dialog
          id="delete_account_modal"
          class="modal"
          onclose="this.querySelector('.modal-box form')?.reset()"
        >
          <div class="modal-box">
            <h3 class="mb-4 text-lg font-bold">
              {t(@locale, "devise.registrations.edit.delete_your_account", %{})}
            </h3>
            <p :if={@self_hosted} class="mb-4 text-sm text-base-content/70">
              {t(
                @locale,
                "devise.registrations.edit.this_is_permanent_and_removes_all_your_data_this_cannot",
                %{}
              )}
            </p>
            <p :if={!@self_hosted} class="mb-4 text-sm text-base-content/70">
              {t(
                @locale,
                "devise.registrations.edit.this_is_permanent_and_removes_all_your_data_this_cannot_2",
                %{}
              )}
            </p>
            <form
              class="space-y-4"
              action="/users"
              accept-charset="UTF-8"
              method="post"
            >
              <input type="hidden" name="_method" value="delete" /><input
                :if={@rails_csrf_token}
                type="hidden"
                name="authenticity_token"
                value={@rails_csrf_token}
              />
              <div :if={@self_hosted and @oauth != nil} class="form-control">
                <label class="label" for="confirm_email"><span class="label-text">{t(
                  @locale,
                  "devise.registrations.edit.type_your_email",
                  %{}
                )}<span class="font-medium">{@user.email}</span>{t(
                  @locale,
                  "devise.registrations.edit.to_confirm",
                  %{}
                )}</span></label>
                <input
                  type="text"
                  name="confirm_email"
                  id="confirm_email"
                  autocomplete="off"
                  required="required"
                  class="input input-bordered w-full"
                />
              </div>
              <div :if={@self_hosted and @oauth == nil} class="form-control">
                <label class="label" for="password"><span class="label-text">{t(
                  @locale,
                  "devise.registrations.edit.enter_your_current_password_to_confirm",
                  %{}
                )}</span></label>
                <input
                  type="password"
                  name="password"
                  id="password"
                  autocomplete="current-password"
                  required="required"
                  class="input input-bordered w-full"
                />
              </div>
              <div class="modal-action flex-col-reverse sm:flex-row">
                <button
                  type="button"
                  class="btn w-full sm:w-auto"
                  phx-click={JS.dispatch("dawarich:close-dialog", to: "#delete_account_modal")}
                >{t(@locale, "devise.registrations.edit.cancel", %{})}</button>
                <button type="submit" class="btn btn-error w-full sm:w-auto">{@submit}</button>
              </div>
            </form>
          </div>
          <form method="dialog" class="modal-backdrop">
            <button>{t(@locale, "devise.registrations.edit.close", %{})}</button>
          </form>
        </dialog>
      </div>
    </div>
    """
  end
end
