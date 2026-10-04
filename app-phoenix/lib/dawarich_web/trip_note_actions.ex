defmodule DawarichWeb.TripNoteActions do
  @moduledoc false
  @behaviour Plug
  use Phoenix.Component
  import Plug.Conn
  alias Dawarich.{Jobs, Trips.WebNotes}

  alias DawarichWeb.{
    Locale,
    RailsCsrf,
    RailsSession,
    RequestURL,
    Translate,
    TripDaysList,
    TripNoteForm
  }

  alias DawarichWeb.Api.Body

  def init(action), do: action

  def call(conn, :member),
    do: call(conn, if(conn.assigns.a8_action == :note_destroy, do: :destroy, else: :update))

  def call(conn, action) do
    user = conn.assigns.current_user
    trip_id = String.to_integer(conn.path_params["trip_id"])
    id = conn.path_params["id"] && String.to_integer(conn.path_params["id"])
    attrs = conn.assigns.api_params["note"] || %{}
    locale = Locale.resolve(nil, user, conn.assigns.rails_session)
    ctx = %{now: conn.assigns[:now] || DateTime.utc_now(), locale: locale}

    case WebNotes.run(Jobs.repo(), action, user, trip_id, id, attrs, ctx) do
      {:ok, result} ->
        if conn.assigns.a8_format == :turbo_stream do
          render(conn, action, result, trip_id, locale, [])
        else
          redirect(conn, trip_id, nil)
        end

      {:invalid, errors, note} ->
        if conn.assigns.a8_format == :turbo_stream do
          date = NaiveDateTime.to_date(note.noted_at)
          target = if action == :create, do: attrs["date"], else: Date.to_iso8601(date)
          render(conn, :error, %{note: note, date: date, target: target}, trip_id, locale, errors)
        else
          redirect(conn, trip_id, Enum.join(errors, ", "))
        end

      {:invalid_date} ->
        if conn.assigns.a8_format == :turbo_stream,
          do:
            conn
            |> put_resp_header("vary", "Accept")
            |> put_resp_content_type("text/vnd.turbo-stream.html")
            |> send_resp(422, "")
            |> halt(),
          else:
            redirect(
              conn,
              trip_id,
              Translate.t(locale, "controllers.trips.notes.invalid_date", %{})
            )

      {:replay, reason} ->
        Body.replay(conn, reason)

      {:error, :not_found} ->
        DawarichWeb.TripActions.not_found(conn)
    end
  end

  defp render(conn, action, result, trip_id, locale, errors) do
    date = Date.to_iso8601(result.date)
    note = Map.put(result.note, :date, result.date)

    html =
      stream(%{
        __changed__: nil,
        action: action,
        date: date,
        target: Map.get(result, :target, date),
        note: note,
        trip_id: trip_id,
        locale: locale,
        errors: errors,
        csrf: RailsCsrf.masked_token(conn.assigns.rails_session)
      })
      |> Phoenix.HTML.Safe.to_iodata()

    conn
    |> put_resp_header("vary", "Accept")
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_content_type("text/vnd.turbo-stream.html")
    |> send_resp(200, html)
    |> halt()
  end

  defp stream(assigns) do
    ~H"""
    <turbo-stream action="replace" target={"note-#{@trip_id}-#{@target}"}>
      <template>
        <%= case @action do %>
          <% :destroy -> %>
            <TripDaysList.empty_note
              date={@date}
              trip_id={@trip_id}
              locale={@locale}
              rails_csrf_token={@csrf}
            />
          <% :error -> %>
            <turbo-frame id={"note-#{@trip_id}-#{@date}"}>
              <TripNoteForm.editor
                note={@note}
                trip_id={@trip_id}
                date={@date}
                locale={@locale}
                csrf={@csrf}
                errors={@errors}
                mode={:error}
              />
            </turbo-frame>
          <% _ -> %>
            <TripDaysList.note
              note={@note}
              trip_id={@trip_id}
              locale={@locale}
              rails_csrf_token={@csrf}
            />
        <% end %>
      </template>
    </turbo-stream>
    """
  end

  defp redirect(conn, trip_id, alert) do
    conn =
      if alert,
        do:
          RailsSession.stage(conn, %{
            "flash" => %{"discard" => [], "flashes" => %{"alert" => alert}}
          }),
        else: conn

    conn
    |> put_resp_header("location", RequestURL.base(conn) <> "/trips/#{trip_id}")
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_content_type("text/html")
    |> send_resp(302, "")
    |> halt()
  end
end
