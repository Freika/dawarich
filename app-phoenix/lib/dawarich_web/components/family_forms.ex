defmodule DawarichWeb.FamilyForms do
  @moduledoc false
  use DawarichWeb, :html

  import DawarichWeb.FamilyControls, only: [sharing_toggle: 1, family_danger: 1]

  def new_family(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8">
      <div class="max-w-2xl mx-auto">
        <div class="text-center mb-8">
          <h1 class="text-3xl font-bold text-base-content mb-4">{n(@locale, "title")}</h1><p class="text-base-content opacity-60">
            {n(@locale, "description")}
          </p>
        </div>
        <%= if @page.state == :upgrade do %>
          <div class="bg-base-200 rounded-lg p-6 text-center">
            <h2 class="text-xl font-bold mb-2">{n(@locale, "upgrade_title")}</h2><p class="text-base-content opacity-60 mb-6">
              {n(@locale, "upgrade_description")}
            </p>
            <a href={@upgrade_href} target="_blank" rel="noopener noreferrer" class="btn btn-primary">{n(
              @locale,
              "upgrade_cta"
            )}</a>
          </div>
        <% else %>
          <div class="bg-base-200 rounded-lg p-6">
            <form class="space-y-6" action="/family" accept-charset="UTF-8" method="post">
              <input
                type="hidden"
                name="authenticity_token"
                value={@rails_csrf_token}
              />
              <.name_field locale={@locale} value={nil} scope="new" />
              <div class="alert alert-info">
                <div>
                  <h3 class="text-sm font-medium mb-2">{n(@locale, "what_happens_title")}</h3><ul class="text-sm space-y-1">
                    <li :for={i <- 1..4}>• {n(@locale, "what_happens_#{i}")}</li>
                  </ul>
                </div>
              </div>
              <div class="flex items-center justify-between">
                <input
                  type="submit"
                  name="commit"
                  value={n(@locale, "create_family")}
                  class="btn btn-primary"
                  data-disable-with={n(@locale, "create_family")}
                /><a href="/" class="btn btn-ghost">{n(@locale, "back")}</a>
              </div>
            </form>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  def lapsed_family(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8">
      <div class="max-w-2xl mx-auto">
        <div class="text-center mb-8">
          <h1 class="text-3xl font-bold text-base-content mb-4">
            {l(@locale, "family_plan_no_longer_active")}
          </h1>
          <p class="text-base-content opacity-60">
            {l(
              @locale,
              if(@page.owner?,
                do: "your_family_plan_is_no_longer_active_so_family_features",
                else: "your_family_s_plan_is_no_longer_active_so_family"
              )
            )}
          </p>
        </div>
        <div class="bg-base-200 rounded-lg p-6">
          <div :if={@page.owner?} class="text-center mb-6">
            <a href={@upgrade_href} target="_blank" rel="noopener noreferrer" class="btn btn-primary">{l(
              @locale,
              "renew_family_plan"
            )}</a>
          </div>
          <div :if={@page.owner? and @page.invitations != []} class="text-center mb-6">
            <a href="/family/invitations" class="link text-sm">{l(@locale, "view_pending_invitations")}</a>
          </div>
          <div :if={@page.owner? and length(@page.members) > 1} class="mb-6">
            <h2 class="text-sm font-medium mb-2">{l(@locale, "members")}</h2><ul class="space-y-2">
              <li
                :for={member <- @page.members}
                :if={member.id != @page.actor_id}
                class="flex items-center justify-between"
              >
                <span class="text-sm">{member.email}</span><a
                  href={"/family/members/#{member.membership_id}"}
                  data-turbo-confirm={
                    t(@locale, "families.lapsed.remove_email_from_the_family", %{email: member.email})
                  }
                  data-turbo-method="delete"
                  class="btn btn-ghost btn-xs text-warning"
                >{l(@locale, "remove")}</a>
              </li>
            </ul>
          </div>
          <div class="mb-6">
            <h2 class="text-sm font-medium mb-2">{l(@locale, "your_location_sharing")}</h2><.sharing_toggle
              member={@page.me}
              locale={@locale}
              now={@now}
              rails_csrf_token={@rails_csrf_token}
            />
          </div>
          <.family_danger page={@page} locale={@locale} scope="families.lapsed" />
        </div>
      </div>
    </div>
    """
  end

  def edit_family(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8">
      <div class="max-w-2xl mx-auto">
        <div class="bg-base-200 rounded-lg p-6">
          <div class="flex items-center justify-between mb-6">
            <h1 class="text-2xl font-bold text-base-content">{e(@locale, "title")}</h1><a
              href="/family"
              class="btn btn-ghost"
            >{e(@locale, "back")}</a>
          </div>
          <form
            class="space-y-6"
            action={"/family.#{@page.family.id}"}
            accept-charset="UTF-8"
            method="post"
          >
            <input type="hidden" name="_method" value="patch" />
            <input
              type="hidden"
              name="authenticity_token"
              value={@rails_csrf_token}
            />
            <.name_field locale={@locale} value={@page.family.name} scope="edit" />
            <div class="bg-base-300 p-4 rounded-md">
              <h3 class="text-sm font-medium text-base-content mb-2">{e(@locale, "family_info")}</h3><dl class="grid grid-cols-1 gap-x-4 gap-y-2 sm:grid-cols-2">
                <div>
                  <dt class="text-sm font-medium text-base-content opacity-60">
                    {e(@locale, "creator")}
                  </dt><dd class="text-sm text-base-content">{@page.family.creator_email}</dd>
                </div>
                <div>
                  <dt class="text-sm font-medium text-base-content opacity-60">
                    {e(@locale, "created_on")}
                  </dt><dd class="text-sm text-base-content">
                    {DawarichWeb.LocalizedDate.l(@locale, @page.family.created_date, "long")}
                  </dd>
                </div>
                <div>
                  <dt class="text-sm font-medium text-base-content opacity-60">
                    {e(@locale, "members_count")}
                  </dt><dd class="text-sm text-base-content">
                    {t(@locale, "families.edit.member_count", %{count: @page.member_count})}
                  </dd>
                </div>
                <div>
                  <dt class="text-sm font-medium text-base-content opacity-60">
                    {e(@locale, "last_updated")}
                  </dt><dd class="text-sm text-base-content">
                    {DawarichWeb.LocalizedDate.l(@locale, @page.family.updated_date, "long")}
                  </dd>
                </div>
              </dl>
            </div>
            <div class="flex items-center justify-between pt-4">
              <div class="flex space-x-3">
                <input
                  type="submit"
                  name="commit"
                  value={e(@locale, "save_changes")}
                  class="btn btn-primary"
                  data-disable-with={e(@locale, "save_changes")}
                /><a href="/family" class="btn btn-neutral">{e(@locale, "cancel")}</a>
              </div>
              <a
                :if={@page.owner?}
                href="/family"
                data-turbo-confirm={e(@locale, "are_you_sure_you_want_to_delete_this_family_this")}
                data-turbo-method="delete"
                class="btn btn-outline btn-error"
              ><DawarichWeb.Icon.icon name="trash-2" class="inline-block w-4" /> {e(
                @locale,
                "delete_family"
              )}</a>
            </div>
          </form>
        </div>
      </div>
    </div>
    """
  end

  def name_field(assigns) do
    ~H"""
    <div>
      <label class="label label-text font-medium mb-2" for="family_name">{t(
        @locale,
        "families.form.name",
        %{}
      )}</label>
      <input
        type="text"
        name="family[name]"
        id="family_name"
        value={@value}
        class="input input-bordered w-full"
        placeholder={t(@locale, "families.form.name_placeholder", %{})}
      />
      <p class="mt-1 text-sm text-base-content opacity-50">
        {t(@locale, "families." <> @scope <> ".name_help", %{})}
      </p>
    </div>
    """
  end

  defp n(locale, key), do: t(locale, "families.new." <> key, %{})
  defp l(locale, key), do: t(locale, "families.lapsed." <> key, %{})
  defp e(locale, key), do: t(locale, "families.edit." <> key, %{})
end
