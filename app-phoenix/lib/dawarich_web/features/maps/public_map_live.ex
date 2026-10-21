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
    ~H"""
    <DawarichWeb.NativePublicChrome.header {assigns} />
    <main
      data-native-map-root
      data-map-ready={to_string(@public_map_ready)}
    >
      <%= cond do %>
        <% @public_config && DawarichWeb.PublicMapShell.simple?(@public_presentation) -> %>
          <DawarichWeb.PublicMapShell.content {assigns} />
        <% @public_config -> %>
          <DawarichWeb.NativePublicResource.resource
            presentation={@public_presentation}
            config={@public_config}
            selected_day={@public_selected_day}
            gallery_days={@public_gallery_days}
            locale={@locale || "en"}
          />
        <% true -> %>
          <DawarichWeb.PublicMapShell.unavailable {assigns} />
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
