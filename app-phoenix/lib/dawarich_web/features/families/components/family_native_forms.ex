defmodule DawarichWeb.FamilyNativeForms do
  @moduledoc false
  use DawarichWeb, :html
  alias DawarichWeb.FamilyNativeControls

  def native_form(assigns) do
    ~H"""
    <div id="native-family-form-shell" class="container mx-auto px-4 py-8">
      <div class="max-w-2xl mx-auto">
        <%= case @page.state do %>
          <% :lapsed -> %>
            <DawarichWeb.NativeFamilyLapsed.lapsed {assigns} />
          <% :edit -> %>
            <.edit {assigns} />
          <% _ -> %>
            <div class="text-center mb-8">
              <h1 class="text-3xl font-bold text-base-content mb-4">{s(@locale, "new.title")}</h1><p class="text-base-content opacity-60">
                {s(@locale, "new.description")}
              </p>
            </div>
            <%= if @page.state == :upgrade do %>
              <div class="bg-base-200 rounded-lg p-6 text-center">
                <h2 class="text-xl font-bold mb-2">{s(@locale, "new.upgrade_title")}</h2><p class="text-base-content opacity-60 mb-6">
                  {s(@locale, "new.upgrade_description")}
                </p><a
                  href="/native/family/upgrade"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="btn btn-primary"
                >{s(@locale, "new.upgrade_cta")}</a>
              </div>
            <% else %>
              <div class="bg-base-200 rounded-lg p-6">
                <form
                  id="native-family-form"
                  class="space-y-6"
                  action="/family"
                  accept-charset="UTF-8"
                  method="post"
                  phx-submit="family_save"
                >
                  <input type="hidden" name="authenticity_token" value={@rails_csrf_token} />
                  <FamilyNativeControls.errors errors={@errors} />
                  <.name {assigns} action="new" />
                  <div class="alert alert-info">
                    <div>
                      <h3 class="text-sm font-medium mb-2">{s(@locale, "new.what_happens_title")}</h3><ul class="text-sm space-y-1">
                        <li :for={i <- 1..4}>• {s(@locale, "new.what_happens_#{i}")}</li>
                      </ul>
                    </div>
                  </div>
                  <div class="flex items-center justify-between">
                    <input
                      type="submit"
                      name="commit"
                      value={s(@locale, "new.create_family")}
                      class="btn btn-primary"
                      phx-disable-with={s(@locale, "new.create_family")}
                    /><a class="btn btn-ghost" href="/">{s(@locale, "new.back")}</a>
                  </div>
                </form>
              </div>
            <% end %>
        <% end %>
      </div>
    </div>
    <FamilyNativeControls.confirmation
      :if={@page[:family]}
      confirmation={@confirmation}
      page={@page}
      locale={@locale}
    />
    """
  end

  def edit(assigns) do
    ~H"""
    <div class="bg-base-200 rounded-lg p-6">
      <div class="flex items-center justify-between mb-6">
        <h1 class="text-2xl font-bold text-base-content">{s(@locale, "edit.title")}</h1><a
          class="btn btn-ghost"
          href="/family"
        >{s(@locale, "edit.back")}</a>
      </div>
      <form
        id="native-family-form"
        class="space-y-6"
        action={"/family.#{@page.family.id}"}
        accept-charset="UTF-8"
        method="post"
        phx-submit="family_save"
      >
        <input type="hidden" name="_method" value="patch" /><input
          type="hidden"
          name="authenticity_token"
          value={@rails_csrf_token}
        />
        <FamilyNativeControls.errors errors={@errors} />
        <.name {assigns} action="edit" />
        <div class="bg-base-300 p-4 rounded-md">
          <h3 class="text-sm font-medium text-base-content mb-2">{s(@locale, "edit.family_info")}</h3><dl class="grid grid-cols-1 gap-x-4 gap-y-2 sm:grid-cols-2">
            <div :for={{key, value} <- info(@page, @locale)}>
              <dt class="text-sm font-medium text-base-content opacity-60">
                {s(@locale, "edit." <> key)}
              </dt><dd class="text-sm text-base-content">{value}</dd>
            </div>
          </dl>
        </div>
        <div class="flex items-center justify-between pt-4">
          <div class="flex space-x-3">
            <input
              type="submit"
              name="commit"
              value={s(@locale, "edit.save_changes")}
              class="btn btn-primary"
              phx-disable-with={s(@locale, "edit.save_changes")}
            /><a class="btn btn-neutral" href="/family">{s(@locale, "edit.cancel")}</a>
          </div>
          <FamilyNativeControls.confirm_button
            :if={@page.owner?}
            action="delete"
            icon="trash-2"
            icon_class="inline-block w-4"
            label={s(@locale, "edit.delete_family")}
            class="btn btn-outline btn-error"
          />
        </div>
      </form>
    </div>
    """
  end

  def name(assigns) do
    ~H"""
    <div>
      <label class="label label-text font-medium mb-2" for="family_name">{s(@locale, "form.name")}</label><input
        class="input input-bordered w-full"
        placeholder={s(@locale, "form.name_placeholder")}
        type="text"
        value={if @page.state == :edit or @errors != [], do: @family_name}
        name="family[name]"
        id="family_name"
      /><p class="mt-1 text-sm text-base-content opacity-50">{s(@locale, @action <> ".name_help")}</p>
    </div>
    """
  end

  defp info(page, locale),
    do: [
      {"creator", page.family.creator_email},
      {"created_on", DawarichWeb.LocalizedDate.l(locale, page.family.created_date, "long")},
      {"members_count", s(locale, "edit.member_count", %{count: page.member_count})},
      {"last_updated", DawarichWeb.LocalizedDate.l(locale, page.family.updated_date, "long")}
    ]

  defp s(locale, key, bindings \\ %{}), do: t(locale, "families." <> key, bindings)
end
