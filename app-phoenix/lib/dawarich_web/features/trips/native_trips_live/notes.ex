defmodule DawarichWeb.NativeTripsLive.Notes do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]

  alias Dawarich.Trips.Notes
  alias DawarichWeb.TripsNative.Access

  @events ~w(note_edit note_draft note_cancel note_save note_delete)

  def events, do: @events

  def handle("note_edit", %{"date" => date}, socket) do
    case day(socket, date) do
      nil -> socket
      day -> put_draft(socket, date, (day.note && day.note.body) || "")
    end
  end

  def handle("note_draft", %{"note" => %{"date" => date, "body" => body}}, socket)
      when is_binary(body) do
    if Map.has_key?(socket.assigns.note_drafts, date),
      do: put_draft(socket, date, body),
      else: socket
  end

  def handle("note_cancel", %{"date" => date}, socket),
    do: socket |> drop(date) |> assign(:note_errors, Map.delete(socket.assigns.note_errors, date))

  def handle("note_save", %{"note" => %{"date" => date, "body" => body}}, socket)
      when is_binary(body) do
    with %{} <- day(socket, date),
         true <- Map.has_key?(socket.assigns.note_drafts, date),
         {:ok, scope} <- Access.scope(socket) do
      case Notes.save(scope, socket.assigns.trip.id, date, body, DateTime.utc_now()) do
        {:ok, %{note: note}} -> socket |> drop(date) |> put_note(date, note)
        {:invalid, errors} -> socket |> put_draft(date, body) |> put_errors(date, errors)
        {:error, reason} -> {:refuse, reason}
      end
    else
      {:error, reason} -> {:refuse, reason}
      _ -> socket
    end
  end

  def handle("note_delete", %{"date" => date}, socket) do
    with %{note: %{id: id}} <- day(socket, date),
         {:ok, scope} <- Access.scope(socket) do
      case Notes.delete(scope, socket.assigns.trip.id, id, DateTime.utc_now()) do
        {:ok, _} -> put_note(socket, date, nil)
        {:error, :not_found} -> put_note(socket, date, nil)
        {:error, reason} -> {:refuse, reason}
      end
    else
      {:error, reason} -> {:refuse, reason}
      _ -> socket
    end
  end

  def handle(_event, _params, socket), do: socket

  defp day(socket, date) when is_binary(date),
    do: Enum.find(socket.assigns.days, &(Date.to_iso8601(&1.date) == date))

  defp day(_socket, _date), do: nil

  defp put_draft(socket, date, body),
    do: assign(socket, :note_drafts, Map.put(socket.assigns.note_drafts, date, body))

  defp drop(socket, date),
    do: assign(socket, :note_drafts, Map.delete(socket.assigns.note_drafts, date))

  defp put_errors(socket, date, errors),
    do: assign(socket, :note_errors, Map.put(socket.assigns.note_errors, date, errors))

  defp put_note(socket, date, note) do
    days =
      Enum.map(socket.assigns.days, fn day ->
        if Date.to_iso8601(day.date) == date, do: %{day | note: note}, else: day
      end)

    socket
    |> assign(:days, days)
    |> assign(:note_errors, Map.delete(socket.assigns.note_errors, date))
  end
end
