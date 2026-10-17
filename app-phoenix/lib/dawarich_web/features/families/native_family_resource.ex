defmodule DawarichWeb.NativeFamilyResource do
  @moduledoc false
  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [attach_hook: 4, push_event: 3]

  def attach(socket) do
    socket
    |> attach_hook(:family_event, :handle_event, fn _, _, s -> admit(s) end)
    |> attach_hook(:family_info, :handle_info, fn
      {:native_family_consent, token}, s ->
        {:halt, DawarichWeb.NativeFamilyConsent.expire(s, token)}

      _, s ->
        admit(s)
    end)
    |> attach_hook(:family_async, :handle_async, fn _, _, s -> admit(s) end)
    |> admit()
    |> elem(1)
  end

  def admit(socket) do
    case Dawarich.Maps.Family.view(socket.assigns.current_scope,
           self_hosted: socket.assigns.self_hosted != false
         ) do
      {:ok, page} ->
        {:cont,
         socket
         |> assign(page: page, page_title: page.presentation.family.name, map_error: nil)
         |> DawarichWeb.NativeFamilyConsent.renew()}

      {:error, reason} ->
        {:halt, refuse(socket, reason)}
    end
  end

  def refuse(socket, reason),
    do:
      socket
      |> assign(confirmation: nil, errors: [])
      |> DawarichWeb.MapLiveAuth.refuse(reason)
      |> push_event("map:clear", %{code: Atom.to_string(reason)})
end
