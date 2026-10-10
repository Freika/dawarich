defmodule DawarichWeb.FamilyNativeForms do
  @moduledoc false
  use DawarichWeb, :html
  alias DawarichWeb.{FamilyNativeControls, FamilyNativeMembers}

  def native_form(assigns) do
    ~H"""
    <section
      id="family-form-shell"
      class="container mx-auto max-w-2xl py-8 min-w-0 [overflow-wrap:anywhere]"
    >
      <FamilyNativeControls.errors errors={@errors} />
      <%= if @page.state in [:create, :edit] do %>
        <h1 class="text-3xl font-bold mb-4">
          {t(
            @locale,
            if(@page.state == :edit, do: "families.edit.title", else: "families.new.title"),
            %{}
          )}
        </h1>
        <p :if={@page.state == :create} class="mb-6">{t(@locale, "families.new.description", %{})}</p>
        <form
          id="native-family-form"
          phx-submit="family_save"
          class="space-y-6 bg-base-200 rounded-lg p-5"
        >
          <div>
            <label for="family_name" class="label label-text">{t(@locale, "families.form.name", %{})}</label>
            <input
              id="family_name"
              type="text"
              name="family[name]"
              value={@family_name}
              class="input input-bordered w-full"
              placeholder={t(@locale, "families.form.name_placeholder", %{})}
            />
            <p class="text-xs mt-2">
              {t(
                @locale,
                if(@page.state == :edit,
                  do: "families.edit.name_help",
                  else: "families.new.name_help"
                ),
                %{}
              )}
            </p>
          </div>
          <div :if={@page.state == :create} class="alert alert-info min-w-0">
            <div>
              <h2 class="font-medium">{t(@locale, "families.new.what_happens_title", %{})}</h2><ul>
                <li :for={i <- 1..4}>{t(@locale, "families.new.what_happens_#{i}", %{})}</li>
              </ul>
            </div>
          </div>
          <div :if={@page.state == :edit} class="space-y-3">
            <h2 class="font-semibold">{t(@locale, "families.edit.family_info", %{})}</h2>
            <dl class="grid sm:grid-cols-2 gap-3">
              <div>
                <dt>{t(@locale, "families.edit.created_on", %{})}</dt><dd>
                  {DawarichWeb.LocalizedDate.l(@locale, @page.family.created_date, "long")}
                </dd>
              </div>
              <div>
                <dt>{t(@locale, "families.edit.creator", %{})}</dt><dd>
                  {@page.family.creator_email}
                </dd>
              </div>
              <div>
                <dt>{t(@locale, "families.edit.members_count", %{})}</dt><dd>
                  {t(@locale, "families.edit.member_count", %{count: @page.member_count})}
                </dd>
              </div>
              <div>
                <dt>{t(@locale, "families.edit.last_updated", %{})}</dt><dd>
                  {DawarichWeb.LocalizedDate.l(@locale, @page.family.updated_date, "long")}
                </dd>
              </div>
            </dl>
          </div>
          <div class="flex flex-wrap gap-3">
            <button
              type="submit"
              class="btn btn-primary h-auto whitespace-normal"
              phx-disable-with={t(@locale, "javascript.common.save", %{})}
            >{t(
              @locale,
              if(@page.state == :edit,
                do: "families.edit.save_changes",
                else: "families.new.create_family"
              ),
              %{}
            )}</button>
            <a
              href={if @page.state == :edit, do: "/family", else: "/"}
              class="btn btn-ghost h-auto whitespace-normal"
            >{t(
              @locale,
              if(@page.state == :edit, do: "families.edit.cancel", else: "families.new.back"),
              %{}
            )}</a>
            <FamilyNativeControls.confirm_button
              :if={@page.state == :edit}
              action="delete"
              label={t(@locale, "families.edit.delete_family", %{})}
            />
          </div>
        </form>
      <% else %>
        <h1 class="text-3xl font-bold mb-4">
          {t(
            @locale,
            if(@page.state == :lapsed,
              do: "families.lapsed.family_plan_no_longer_active",
              else: "families.new.title"
            ),
            %{}
          )}
        </h1>
        <div class="bg-base-200 p-5 rounded-lg space-y-6">
          <%= if @page.state == :upgrade do %>
            <h2 class="text-xl font-semibold">{t(@locale, "families.new.upgrade_title", %{})}</h2>
            <p>{t(@locale, "families.new.upgrade_description", %{})}</p>
            <a
              href="/native/family/upgrade"
              target="_blank"
              rel="noopener noreferrer"
              class="btn btn-primary h-auto whitespace-normal"
            >{t(@locale, "families.new.upgrade_cta", %{})}</a>
          <% else %>
            <p>
              {t(
                @locale,
                if(@page.owner?,
                  do: "families.lapsed.your_family_plan_is_no_longer_active_so_family_features",
                  else: "families.lapsed.your_family_s_plan_is_no_longer_active_so_family"
                ),
                %{}
              )}
            </p>
            <a
              :if={@page.owner?}
              href="/native/family/upgrade"
              target="_blank"
              rel="noopener noreferrer"
              class="btn btn-primary h-auto whitespace-normal"
            >{t(@locale, "families.lapsed.renew_family_plan", %{})}</a>
            <a
              :if={@page.owner? and @page[:invitations] != []}
              href="/family/invitations"
              class="link"
            >{t(@locale, "families.lapsed.view_pending_invitations", %{})}</a>
            <FamilyNativeMembers.members
              :if={@page.owner?}
              page={@page}
              locale={@locale}
              now={@now}
              self_hosted={@self_hosted}
            />
            <h2 class="font-semibold">{t(@locale, "families.lapsed.your_location_sharing", %{})}</h2>
            <FamilyNativeControls.sharing
              member={@page.me}
              locale={@locale}
              now={@now}
              current_scope={@current_scope}
            />
            <FamilyNativeControls.danger page={@page} locale={@locale} />
          <% end %>
        </div>
      <% end %>
      <FamilyNativeControls.confirmation confirmation={@confirmation} page={@page} locale={@locale} />
    </section>
    """
  end
end
