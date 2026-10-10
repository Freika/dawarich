defmodule DawarichWeb.PublicShareLive do
  @moduledoc false
  use DawarichWeb, :live_view
  alias Dawarich.Sharing.Public

  def mount(_, session, socket) do
    socket =
      assign(socket, grant: nil, page: nil, public_expiry: nil, locale: session["locale"] || "en")

    socket =
      case DawarichWeb.PublicShareAuth.verify(session, socket) do
        {:ok, grant} ->
          if connected?(socket) do
            Public.subscribe(grant, DateTime.utc_now())

            if grant[:session_topic],
              do: Phoenix.PubSub.subscribe(Dawarich.PubSub, grant.session_topic)
          end

          reload(assign(socket, grant: grant))

        _ ->
          clear(socket)
      end

    {:ok, socket, layout: false}
  end

  def handle_event("public_reload", _, socket), do: {:noreply, reload(socket)}
  def handle_event(_, _, socket), do: {:noreply, reload(socket)}

  def handle_info(:notification_signed_out, socket),
    do: {:noreply, clear(assign(socket, grant: nil))}

  def handle_info(
        {:public_share_expiry, token},
        %{assigns: %{public_expiry: %{token: token}}} = socket
      ), do: {:noreply, reload(socket)}

  def handle_info({:public_share_expiry, _}, socket), do: {:noreply, socket}
  def handle_info(_, socket), do: {:noreply, reload(socket)}

  defp reload(socket) do
    cancel(socket.assigns.public_expiry)

    case Public.read(socket.assigns.grant, DateTime.utc_now()) do
      {:ok, page} -> assign(socket, page: page, public_expiry: timer(socket, page.expires_at))
      _ -> clear(socket)
    end
  end

  defp timer(socket, due) do
    if connected?(socket) do
      token = make_ref()
      delay = max(1, due * 1000 - System.system_time(:millisecond))
      timer = Process.send_after(self(), {:public_share_expiry, token}, delay)
      %{token: token, timer: timer, due: due}
    end
  end

  defp clear(socket) do
    cancel(socket.assigns.public_expiry)
    socket |> assign(page: nil, public_expiry: nil) |> push_event("public-share-clear", %{})
  end

  defp cancel(%{timer: timer}), do: Process.cancel_timer(timer)
  defp cancel(_), do: :ok
  def terminate(_, socket), do: cancel(socket.assigns.public_expiry)

  defp heading(%{kind: {:timeline, from, to}}, locale),
    do: DawarichWeb.SharedPages.date_range(locale, from, to)

  defp heading(page, _), do: page.link.name

  def render(assigns) do
    ~H"""
    <section
      id="native-public-share"
      class="container mx-auto px-4 py-6 min-w-0 [overflow-wrap:anywhere]"
    >
      <div :if={@page} data-public-content>
        <DawarichWeb.SharedPages.missing_resource
          :if={@page.kind == :missing_resource}
          locale={@locale}
        />
        <h1 :if={@page.kind != :missing_resource} class="text-3xl font-bold min-w-0">
          {heading(@page, @locale)}
        </h1>
      </div>
      <DawarichWeb.SharedPages.not_found :if={!@page} locale={@locale} />
    </section>
    """
  end
end
