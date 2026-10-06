defmodule DawarichWeb.NavbarHooks do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1]

  alias Dawarich.Navbar

  @refresh 10_000

  def attach(socket, opts \\ []) do
    if connected?(socket), do: schedule()

    socket = notification_session(socket)

    socket =
      if Keyword.get(opts, :params, true),
        do: attach_hook(socket, :navbar_params, :handle_params, &params/3),
        else: socket

    socket
    |> attach_hook(:navbar_info, :handle_info, &info/2)
    |> attach_hook(:navbar_event, :handle_event, &event/3)
  end

  defp notification_session(%{assigns: %{current_user: %{}}} = socket),
    do: DawarichWeb.NotificationSession.attach(socket)

  defp notification_session(socket), do: socket

  defp params(_params, uri, socket) do
    socket =
      socket
      |> assign(:now, DateTime.utc_now())
      |> assign(:query_params, Plug.Conn.Query.decode(URI.parse(uri).query || ""))

    {:cont, assign(socket, :navbar, load(socket))}
  end

  defp info(:navbar_refresh, socket) do
    schedule()
    {:halt, refresh(socket)}
  end

  defp info(_message, socket), do: {:cont, socket}

  defp event(
         "changelog_consent",
         %{"decision" => decision},
         %{assigns: %{current_user: %{} = user}} = socket
       )
       when decision in ~w(declined granted) do
    socket = assign(socket, :current_user, Navbar.put_changelog_consent(user, decision))
    {:halt, assign(socket, :navbar, load(socket))}
  end

  defp event("changelog_consent", _params, socket), do: {:halt, socket}
  defp event(_event, _params, socket), do: {:cont, socket}

  defp load(socket),
    do:
      Navbar.load(socket.assigns.current_user,
        now: socket.assigns.now,
        self_hosted: socket.assigns.self_hosted
      )

  defp refresh(%{assigns: %{current_user: %{id: id}, navbar: %{} = navbar}} = socket),
    do: assign(socket, :navbar, %{navbar | unread: Navbar.unread(id)})

  defp refresh(socket), do: socket

  defp schedule, do: Process.send_after(self(), :navbar_refresh, @refresh)
end
