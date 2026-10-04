defmodule DawarichWeb.TagsLive.Index do
  @moduledoc false
  use DawarichWeb, :live_view
  import DawarichWeb.Icon, only: [icon: 1]
  alias Dawarich.TagPages
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @impl true
  def mount(_params, _session, socket),
    do: {:ok, assign(socket, page_title: nil)}

  @impl true
  def handle_params(_params, _uri, socket),
    do: {:noreply, assign(socket, tags: TagPages.index(socket.assigns.current_user))}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-full my-5">
      <div class="flex flex-col gap-3 md:flex-row md:items-center md:justify-between mb-6">
        <h1 class="text-3xl font-bold">{t(@locale, "tags.index.tags", %{})}</h1>
        <div class="flex flex-wrap gap-2">
          <a href="/tags/new" class="btn btn-primary btn-sm"><.icon
            name="circle-plus"
            class="w-4 h-4"
          /> {t(
            @locale,
            "tags.index.new_tag",
            %{}
          )}</a>
        </div>
      </div>
      <%= if @tags != [] do %>
        <div class="border border-base-300 rounded-xl overflow-x-auto">
          <table class="table table-sm w-full">
            <thead class="bg-base-200">
              <tr>
                <th class="px-4 py-3 text-xs uppercase tracking-wider text-base-content/50 w-16">
                  {t(@locale, "tags.index.icon", %{})}
                </th>
                <th class="px-4 py-3 text-xs uppercase tracking-wider text-base-content/50">
                  {t(@locale, "tags.index.name", %{})}
                </th>
                <th class="px-4 py-3 text-xs uppercase tracking-wider text-base-content/50">
                  {t(@locale, "tags.index.color", %{})}
                </th>
                <th class="px-4 py-3 text-xs uppercase tracking-wider text-base-content/50 text-right">
                  {t(@locale, "tags.index.places", %{})}
                </th>
                <th class="px-4 py-3 text-xs uppercase tracking-wider text-base-content/50 text-right">
                  {t(@locale, "tags.index.actions", %{})}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr :for={tag <- @tags} class="hover:bg-base-200/50 transition-colors">
                <td class="px-4 py-3 text-2xl">{tag.icon}</td>
                <td class="px-4 py-3">
                  <div class="flex items-center gap-2">
                    <span class="font-medium">#{tag.name}</span>
                    <span
                      :if={not is_nil(tag.privacy_radius_meters)}
                      class="inline-flex items-center gap-1 px-2 py-1 rounded-full text-xs font-medium bg-error/10 text-error"
                    ><.icon name="lock-open" class="w-3 h-3" /> {tag.privacy_radius_meters}m</span>
                  </div>
                </td>
                <td class="px-4 py-3">
                  <%= if not Ruby.blank?(tag.color) do %>
                    <div class="flex items-center gap-2">
                      <div
                        class="w-5 h-5 rounded-md border border-base-300"
                        style={"background-color: #{tag.color};"}
                      >
                      </div><span class="text-xs text-base-content/50 font-mono">{tag.color}</span>
                    </div>
                  <% else %>
                    <span class="text-base-content/30 text-sm">--</span>
                  <% end %>
                </td>
                <td class="px-4 py-3 text-right tabular-nums">{tag.places_count}</td>
                <td class="px-4 py-3 text-right">
                  <div class="flex gap-1 justify-end">
                    <div class="tooltip" data-tip={t(@locale, "tags.index.edit_tag", %{})}>
                      <a href={"/tags/#{tag.id}/edit"} class="btn btn-ghost btn-xs"><.icon
                        name="square-pen"
                        class="w-4 h-4"
                      /></a>
                    </div>
                    <div
                      class="tooltip tooltip-left"
                      data-tip={t(@locale, "tags.index.delete_tag", %{})}
                    >
                      <form class="button_to" method="post" action={"/tags/#{tag.id}"}>
                        <input type="hidden" name="_method" value="delete" />
                        <button
                          data-turbo-confirm={t(@locale, "tags.index.are_you_sure", %{})}
                          data-turbo-method="delete"
                          class="btn btn-ghost btn-xs text-error hover:bg-error/10"
                          type="submit"
                        ><.icon name="trash-2" class="w-4 h-4" /></button>
                        <input type="hidden" name="authenticity_token" value={@rails_csrf_token} />
                      </form>
                    </div>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      <% else %>
        <div class="text-center py-16 px-8 bg-base-200 rounded-xl border-2 border-dashed border-base-300">
          <h3 class="text-xl font-bold mb-3">{t(@locale, "tags.index.no_tags_yet", %{})}</h3>
          <p class="text-base-content/50 mb-6 max-w-sm mx-auto">
            {t(@locale, "tags.index.create_tags_to_organize_your_places_and_add_privacy_zones", %{})}
          </p>
          <a href="/tags/new" class="btn btn-primary"><.icon name="circle-plus" class="w-4 h-4" /> {t(
            @locale,
            "tags.index.create_your_first_tag",
            %{}
          )}</a>
        </div>
      <% end %>
    </div>
    """
  end
end
