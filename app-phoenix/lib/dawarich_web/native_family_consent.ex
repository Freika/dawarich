defmodule DawarichWeb.NativeFamilyConsent do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [connected?: 1, push_event: 3]
  alias Dawarich.Families.Clock

  @maximum 30_000

  def renew(%{assigns: %{native_family_consent: %{deadline: deadline}}} = socket) do
    configure(socket, max(0, deadline - System.monotonic_time(:millisecond)))
  end

  def renew(socket) do
    socket = cancel(socket)
    now = DateTime.utc_now()

    milliseconds =
      socket.assigns.page.presentation.members
      |> Enum.filter(& &1.sharing.enabled?)
      |> Enum.map(&Clock.parse(&1.sharing.expires_at))
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&max(0, NaiveDateTime.diff(&1, DateTime.to_naive(now), :millisecond)))
      |> Enum.reduce(@maximum, &min/2)

    socket = configure(socket, milliseconds)

    if connected?(socket) do
      token = make_ref()
      timer = Process.send_after(self(), {:native_family_consent, token}, milliseconds)

      socket
      |> assign(:native_family_consent, %{
        token: token,
        timer: timer,
        milliseconds: milliseconds,
        deadline: System.monotonic_time(:millisecond) + milliseconds
      })
      |> push_event("family:lease", %{milliseconds: milliseconds})
    else
      socket
    end
  end

  def expire(socket, token) do
    case socket.assigns[:native_family_consent] do
      %{token: ^token} ->
        socket = push_event(socket, "family:clear", %{code: "consent_expired"})

        case DawarichWeb.NativeFamilyResource.admit(cancel(socket)) do
          {:cont, socket} -> push_event(socket, "map:invalidate", %{kind: "family"})
          {:halt, socket} -> socket
        end

      _ ->
        socket
    end
  end

  defp configure(socket, milliseconds) do
    page = %{
      socket.assigns.page
      | config: Map.put(socket.assigns.page.config, "consentLeaseMs", milliseconds)
    }

    assign(socket, :page, page)
  end

  def cancel(socket) do
    case socket.assigns[:native_family_consent] do
      %{timer: timer} ->
        Process.cancel_timer(timer)
        assign(socket, :native_family_consent, nil)

      _ ->
        socket
    end
  end
end
