defmodule DawarichWeb.PlacesUI do
  @moduledoc false
  import Phoenix.Component
  import Phoenix.LiveView

  def message(locale),
    do: DawarichWeb.Translate.t(locale, "controllers.application.admin_action_failed", %{})

  def refuse(socket, :stale_session) do
    socket
    |> assign(
      entries: [],
      form_state: nil,
      detail: nil,
      note_state: nil,
      place_data: nil,
      nearby_state: nil,
      confirmation: nil
    )
    |> redirect(to: "/users/sign_in")
  end

  def refuse(socket, _), do: assign(socket, :error, message(socket.assigns.locale))
end
