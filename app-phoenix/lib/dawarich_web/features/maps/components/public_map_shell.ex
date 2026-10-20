defmodule DawarichWeb.PublicMapShell do
  @moduledoc false
  use DawarichWeb, :html

  def simple?(nil), do: true
  def simple?(%{link: %{type: type}}), do: type in ~w(live timeline)

  def content(assigns) do
    type = assigns.public_presentation.link.type
    link = assigns.public_presentation.link

    {from, to} =
      if type == "timeline",
        do:
          {Date.from_iso8601!(link.settings["start_date"]),
           Date.from_iso8601!(link.settings["end_date"])},
        else: {nil, nil}

    assigns = assign(assigns, type: type, link: link, from: from, to: to)

    ~H"""
    <section class="container mx-auto px-4 py-6">
      <%= if @type == "live" do %>
        <div class="flex items-center gap-3 mb-2">
          <h1 class="text-3xl font-bold">{@link.name}</h1>
          <span class="badge badge-error gap-1">{t(@locale, "shared.links.live.live", %{})}</span>
        </div>
        <p data-native-public-status class="text-base-content/70">
          {t(@locale, "shared.links.live.connecting", %{})}
        </p>
        <p data-native-public-last-seen class="text-sm text-base-content/50 mb-4"></p>
      <% else %>
        <header class="mb-4">
          <h1 class="text-3xl font-bold leading-tight">
            {DawarichWeb.SharedPages.date_range(@locale, @from, @to)}
          </h1>
          <p class="text-sm text-base-content/60 mt-1">
            {t(@locale, "shared.links.timeline.days_shared_on_dawarich", %{
              count: Date.diff(@to, @from) + 1
            })}
          </p>
        </header>
      <% end %>
      <DawarichWeb.NativeMapHost.map_host
        id="native-public-map"
        hook="PublicMap"
        config={@public_config}
        locale={@locale}
        style="height: 60vh; min-height: 400px;"
        class={
          if @type == "live",
            do: "rounded-lg overflow-hidden bg-base-200 my-6",
            else: "rounded-lg overflow-hidden bg-base-200 mb-4 ring-1 ring-base-300"
        }
        loading={false}
      />
    </section>
    """
  end

  def unavailable(assigns) do
    ~H"""
    <%= if @public_error == :locked do %>
      <DawarichWeb.SharedPages.phrase_prompt
        locale={@locale}
        link={%{id: @public_capability.id}}
        error={nil}
        rails_session={%{}}
        token={@public_unlock_token}
      />
    <% else %>
      <DawarichWeb.SharedPages.not_found locale={@locale} />
    <% end %>
    """
  end
end
