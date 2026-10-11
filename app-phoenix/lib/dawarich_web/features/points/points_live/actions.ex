defmodule DawarichWeb.PointsLive.Actions do
  @moduledoc false
  import Phoenix.Component, only: [assign: 2, assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3, push_patch: 2]
  alias Dawarich.Points.{Commands, Pages}
  alias DawarichWeb.{NativeDataAuth, PointListFormat, Translate}

  def reset(socket),
    do: socket |> assign(selected: MapSet.new(), point_dialog: nil) |> intent(nil)

  def event("select_all", _params, socket) do
    ids =
      if MapSet.size(socket.assigns.selected) == length(socket.assigns.rows),
        do: [],
        else: Enum.map(socket.assigns.rows, &to_string(&1.id))

    select(socket, ids)
  end

  def event("select_point", %{"id" => id}, socket) when is_binary(id) do
    selected = Enum.map(socket.assigns.selected, &to_string/1)
    ids = if id in selected, do: List.delete(selected, id), else: [id | selected]
    select(socket, ids)
  end

  def event("confirm_delete", _, socket) do
    socket
    |> intent(%{
      action: :delete,
      ids: Enum.map(socket.assigns.selected, &to_string/1),
      query: socket.assigns.query
    })
    |> assign(:point_dialog, :delete)
  end

  def event("export", %{"format" => format}, socket) when format in ["json", "gpx"] do
    socket
    |> intent(%{
      action: :export,
      format: format,
      request_id: Ecto.UUID.generate(),
      query: socket.assigns.query
    })
    |> assign(:point_dialog, :export)
  end

  def event("cancel_action", _, socket), do: socket |> intent(nil) |> assign(:point_dialog, nil)

  def event("confirm_action", _, socket) do
    with {:ok, scope} <- NativeDataAuth.scope(socket),
         %{action: action} = request <- socket.private[:point_intent] do
      result =
        case action do
          :delete ->
            Commands.delete(scope, request.query, request.ids, opts(socket))

          :export ->
            Commands.request_export(
              scope,
              request.query,
              request.format,
              request.request_id,
              opts(socket)
            )
        end

      case result do
        {:ok, result} ->
          socket =
            socket
            |> assign(:point_dialog, nil)
            |> put_flash(:info, Translate.t(socket.assigns.locale, result.notice, %{}))

          if action == :delete,
            do:
              socket
              |> intent(nil)
              |> push_patch(to: PointListFormat.url("/points", request.query)),
            else: socket

        {:error, reason} ->
          NativeDataAuth.refuse(socket, reason)
      end
    else
      {:error, reason} -> NativeDataAuth.refuse(socket, reason)
      _ -> socket
    end
  end

  def event(_, _, socket), do: NativeDataAuth.refuse(socket, :invalid_input)

  defp select(socket, ids) do
    with {:ok, scope} <- NativeDataAuth.scope(socket),
         {:ok, ids} <- Pages.selection(scope, socket.assigns.query, ids, opts(socket)) do
      assign(socket, :selected, MapSet.new(ids))
    else
      {:error, :unauthorized} -> NativeDataAuth.refuse(socket, :invalid_input)
      {:error, reason} -> NativeDataAuth.refuse(socket, reason)
    end
  end

  defp opts(socket), do: [now: DateTime.utc_now(), self_hosted: socket.assigns.self_hosted]

  defp intent(socket, value),
    do: %{socket | private: Map.put(socket.private, :point_intent, value)}
end
