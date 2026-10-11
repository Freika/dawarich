defmodule DawarichWeb.NativeTripNotes do
  @moduledoc false
  import Phoenix.Component, only: [assign: 2, assign: 3]
  alias DawarichWeb.NativeTripState

  def handle_event(event, params, socket) do
    case NativeTripState.refresh(socket) do
      {:ok, socket} -> {:noreply, command(event, params, socket)}
      {:error, socket} -> {:noreply, socket}
    end
  end

  defp command("trip:note:edit", %{"day" => date}, socket) do
    editor =
      case NativeTripState.day(socket, date) do
        nil -> nil
        day -> %{date: date, body: bounded_body(day.note && day.note.body), errors: []}
      end

    assign(socket, note_editor: editor, selected_day: editor && date)
  end

  defp command("trip:note:cancel", _, socket), do: assign(socket, :note_editor, nil)

  defp command("trip:note:save", %{"note" => %{"body" => body}}, socket)
       when is_binary(body) do
    case socket.assigns.note_editor do
      %{date: date} -> change(socket, date, :save, body)
      _ -> socket
    end
  end

  defp command("trip:note:delete", %{"day" => date}, socket),
    do: change(socket, date, :destroy, nil)

  defp command(_, _, socket), do: socket

  defp change(socket, date, action, body) do
    case NativeTripState.day(socket, date) do
      nil -> assign(socket, :note_editor, nil)
      day -> persist(socket, day, date, action, body)
    end
  end

  defp persist(socket, day, date, action, body) do
    note_id = day.note && day.note.id

    result =
      with {:ok, fresh} <- Dawarich.Maps.admit(socket.assigns.current_scope) do
        case action do
          :save ->
            Dawarich.Trips.Notes.save(
              fresh,
              socket.assigns.page.presentation.id,
              date,
              body,
              DateTime.utc_now(),
              repo: Dawarich.Repo
            )

          :destroy ->
            Dawarich.Trips.Notes.delete(
              fresh,
              socket.assigns.page.presentation.id,
              note_id,
              DateTime.utc_now(),
              repo: Dawarich.Repo
            )
        end
      end

    case result do
      {:ok, _} ->
        case NativeTripState.refresh(assign(socket, :note_editor, nil)) do
          {:ok, socket} -> socket
          {:error, socket} -> socket
        end

      {:invalid, errors} ->
        assign(socket, :note_editor, %{date: date, body: bounded_body(body), errors: errors})

      _ ->
        assign(socket, :note_editor, %{
          date: date,
          body: bounded_body(body),
          errors: [
            DawarichWeb.Translate.t(
              socket.assigns.locale,
              "controllers.trips.notes.invalid_date",
              %{}
            )
          ]
        })
    end
  end

  defp bounded_body(body) when is_binary(body),
    do: body |> String.codepoints() |> Enum.take(10_000) |> Enum.join()

  defp bounded_body(_), do: nil
end
