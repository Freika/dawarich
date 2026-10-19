defmodule DawarichWeb.PublicMapLive do
  @moduledoc false
  use DawarichWeb, :live_view
  on_mount({DawarichWeb.PublicMapAuth, :default})

  def mount(_, session, socket) do
    if !connected?(socket) && session["public_record_visit"] != false,
      do: Dawarich.Maps.Public.record_visit(socket.assigns.public_capability)

    socket =
      assign(socket,
        public_map_ready: false,
        public_selected_day: nil,
        public_gallery_days: MapSet.new(),
        public_unlock_token: session["public_unlock_token"]
      )

    socket =
      if socket.assigns.public_config do
        DawarichWeb.MapLive.Subscriptions.sync(socket, %{
          kind: :public,
          capability: socket.assigns.public_capability
        })
      else
        socket
      end

    {:ok, socket}
  end

  def handle_params(_, _, socket), do: {:noreply, socket}

  def handle_event(
        "changelog_consent",
        %{"decision" => decision},
        %{assigns: %{current_scope: scope}} = socket
      )
      when not is_nil(scope) and decision in ~w(declined granted) do
    Dawarich.Maps.with_actor(scope, fn user ->
      Dawarich.Navbar.put_changelog_consent(user, decision)
      :ok
    end)

    {_, socket} = DawarichWeb.PublicMapAuth.authorize(socket)
    {:noreply, socket}
  end

  def handle_event("public:more", _, socket) do
    resource = socket.assigns.public_presentation && socket.assigns.public_presentation.resource

    if resource && is_binary(resource[:next_cursor]) do
      socket = assign(socket, public_cursor: resource.next_cursor, public_selected_day: nil)
      {_, socket} = DawarichWeb.PublicMapAuth.authorize(socket)
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("public:gallery", %{"day" => day, "open" => open}, socket)
      when is_binary(day) and is_boolean(open) do
    resource = socket.assigns.public_presentation && socket.assigns.public_presentation.resource

    if resource && Enum.any?(resource.days, &(to_string(&1.date) == day)) do
      days = socket.assigns.public_gallery_days
      days = if open, do: MapSet.put(days, day), else: MapSet.delete(days, day)
      {:noreply, assign(socket, :public_gallery_days, days)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("public:day", %{"day" => day}, socket) when is_binary(day) do
    resource = socket.assigns.public_presentation && socket.assigns.public_presentation.resource

    if resource && Enum.any?(resource.days, &(to_string(&1.date) == day)) do
      selected = if socket.assigns.public_selected_day == day, do: nil, else: day

      {:noreply,
       socket
       |> assign(:public_selected_day, selected)
       |> push_event("public:day", %{day: selected})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("map:ready", params, socket) do
    current = socket.assigns.public_config
    ready = current && params["revision"] == current["revision"]
    {:noreply, assign(socket, :public_map_ready, ready == true)}
  end

  def handle_event("map:failed", _, socket),
    do: {:noreply, assign(socket, :public_map_ready, false)}

  def handle_event(_, _, socket), do: {:noreply, socket}

  def handle_info({:public_map_expiry, token}, socket),
    do: {:noreply, DawarichWeb.PublicMapDeadline.receive_expiry(socket, token)}

  def handle_info(message, socket) do
    {_, socket} = DawarichWeb.MapLive.Subscriptions.deliver(socket, message)
    {:noreply, socket}
  end

  def render(assigns) do
    link = assigns.public_presentation && assigns.public_presentation.link
    visible = link && (link.type not in ["trip", "track"] || link.settings["show_route"] != false)
    resource = assigns.public_presentation && assigns.public_presentation.resource

    title =
      (resource && resource[:name]) || (assigns.public_config && assigns.public_config["title"])

    assigns = assign(assigns, map_visible: visible, public_title: title)

    ~H"""
    <DawarichWeb.NativePublicChrome.header {assigns} />
    <main
      data-native-map-root
      class="mx-auto w-full min-w-0 max-w-7xl p-4"
      data-map-ready={to_string(@public_map_ready)}
    >
      <%= if @public_config do %>
        <h1 class="mb-4 break-words text-3xl font-bold [overflow-wrap:anywhere]">
          {@public_title}
        </h1>
        <DawarichWeb.NativePublicResource.resource
          presentation={@public_presentation}
          selected_day={@public_selected_day}
          gallery_days={@public_gallery_days}
          locale={@locale || "en"}
        />
        <DawarichWeb.MapReplay.opener
          :if={@map_visible}
          id="native-public-replay"
          locale={@locale || "en"}
        />
        <DawarichWeb.MapReplay.replay_panel
          :if={@map_visible}
          id="native-public-replay"
          locale={@locale || "en"}
          show_day_nav
          native
          hook="native"
        />
        <DawarichWeb.NativeMapHost.map_host
          :if={@map_visible}
          id="native-public-map"
          hook="PublicMap"
          config={@public_config}
          locale={@locale || "en"}
          class="h-[70vh] min-h-80 w-full min-w-0 rounded-lg"
        />
      <% else %>
        <%= if @public_error == :locked do %>
          <section class="mx-auto max-w-md py-8 text-center">
            <h1 class="text-3xl font-bold">
              {t(@locale, "shared.links.phrase_prompt.enter_the_magic_phrase", %{})}
            </h1>
            <p class="py-4">
              {t(
                @locale,
                "shared.links.phrase_prompt.this_shared_link_is_protected_ask_the_owner_for_the",
                %{}
              )}
            </p>
            <form action={"/s/#{@public_capability.id}/unlock"} method="post" class="form-control">
              <input type="hidden" name="authenticity_token" value={@public_unlock_token} />
              <label for="public-phrase" class="label">{t(
                @locale,
                "shared.links.phrase_prompt.magic_phrase",
                %{}
              )}</label>
              <input
                id="public-phrase"
                name="phrase"
                type="text"
                required
                class="input input-bordered w-full min-w-0"
              />
              <button class="btn btn-primary mt-4 h-auto min-h-12 whitespace-normal">{t(
                @locale,
                "shared.links.phrase_prompt.unlock",
                %{}
              )}</button>
            </form>
          </section>
        <% else %>
          <section role="status" class="mx-auto max-w-md py-8 text-center">
            <h1 class="text-3xl font-bold">
              {t(@locale, "shared.links.not_found.this_shared_link_is_no_longer_available", %{})}
            </h1>
            <p class="py-4">
              {t(@locale, "shared.links.not_found.the_owner_may_have_revoked_the_link_or_it_may", %{})}
            </p>
          </section>
        <% end %>
      <% end %>
    </main>
    <DawarichWeb.NativePublicChrome.footer :if={!@current_scope} locale={@locale} />
    <.live_component
      :if={@current_scope && @navbar}
      module={DawarichWeb.OnboardingLiveComponent}
      id="onboarding"
      scope={@current_scope}
      navbar={@navbar}
      locale={@locale}
      base_url={@base_url}
      rails_csrf_token={@rails_csrf_token}
      auto_open={false}
    />
    """
  end
end
