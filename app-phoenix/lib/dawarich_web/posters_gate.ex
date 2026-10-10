defmodule DawarichWeb.PostersGate do
  @moduledoc false
  import Plug.Conn
  alias DawarichWeb.{Locale, RailsForm, RailsSession, RequestURL, Translate}
  alias DawarichWeb.Api.Body

  def init(opts), do: opts

  def native?(conn, _params), do: conn.method in ~w(POST DELETE)

  def call(conn, _opts) do
    locale = Locale.resolve(nil, conn.assigns.current_user, conn.assigns.rails_session)
    conn = assign(conn, :locale, locale)

    if is_nil(conn.assigns.current_user) do
      if requested_format(conn, conn.assigns.api_params) == :json do
        reason =
          if conn.assigns[:rails_locked],
            do: "devise.failure.locked",
            else: "devise.failure.unauthenticated"

        conn
        |> DawarichWeb.RailsHeaders.call([])
        |> put_resp_content_type("application/json")
        |> send_resp(
          401,
          Jason.encode!(%{
            error: Translate.t(locale, reason, %{})
          })
        )
        |> halt()
      else
        guest(conn, locale)
      end
    else
      admission =
        conn
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> RailsForm.admission()

      case admission do
        :ok -> conn
        {:replay, reason} -> Body.replay(conn, reason)
      end
    end
  end

  defp guest(conn, locale) do
    locked = conn.assigns[:rails_locked]
    reason = if locked, do: "devise.failure.locked", else: "devise.failure.unauthenticated"

    changes = %{
      "flash" => %{"discard" => [], "flashes" => %{"alert" => Translate.t(locale, reason, %{})}}
    }

    changes =
      if locked == :session,
        do:
          Map.merge(changes, %{"warden.user.user.key" => nil, "warden.user.user.session" => nil}),
        else: changes

    conn
    |> RailsSession.stage(changes)
    |> DawarichWeb.RailsHeaders.call([])
    |> put_resp_header("location", RequestURL.base(conn) <> "/users/sign_in")
    |> put_resp_content_type("text/html")
    |> send_resp(302, "")
    |> halt()
  end

  def supported?(_conn, params) do
    Enum.all?(params, fn {key, value} ->
      (key in ~w(authenticity_token commit format id) and is_binary(value)) or
        (key == "poster" and (is_map(value) or is_binary(value)))
    end)
  end

  def format(conn, params) do
    formats = formats(conn, params)
    Enum.find(formats, &(&1 in [:turbo, :html])) || List.first(formats) || :other
  end

  defp requested_format(conn, params), do: List.first(formats(conn, params)) || :other

  defp formats(conn, params) do
    accept = get_req_header(conn, "accept") |> Enum.join(",")
    xhr = get_req_header(conn, "x-requested-with") == ["XMLHttpRequest"]

    cond do
      params["format"] not in [nil, ""] ->
        [extension(params["format"])]

      not xhr and DawarichWeb.Strangler.browser_like?(accept) ->
        [:html]

      accept == "" and Body.kind(conn) == :json ->
        [:json]

      accept == "" ->
        [:html]

      true ->
        accept
        |> String.split(",", trim: true)
        |> Enum.with_index()
        |> Enum.map(fn {type, index} ->
          [mime | params] = String.split(type, ";", trim: true)
          mime = String.trim(mime)

          quality =
            Enum.find_value(params, if(mime == "*/*", do: "0", else: "1"), fn param ->
              case String.split(String.trim(param), "=", parts: 2) do
                ["q", value] -> String.trim(value, "\"")
                _ -> nil
              end
            end)

          quality =
            case Float.parse(quality) do
              {number, _} -> number
              :error -> 0.0
            end

          {mime, -quality, index}
        end)
        |> Enum.sort_by(fn {_, quality, index} -> {quality, index} end)
        |> Enum.flat_map(fn {mime, _, _} -> mime_formats(mime) end)
    end
  end

  defp extension("html"), do: :html
  defp extension("turbo_stream"), do: :turbo
  defp extension("json"), do: :json
  defp extension(_), do: :other

  defp mime_formats("text/vnd.turbo-stream.html"), do: [:turbo]
  defp mime_formats("text/html"), do: [:html]
  defp mime_formats("application/xhtml+xml"), do: [:html]
  defp mime_formats("application/json"), do: [:json]
  defp mime_formats("text/x-json"), do: [:json]
  defp mime_formats("text/*"), do: [:html, :json, :turbo]
  defp mime_formats("application/*"), do: [:html, :json]
  defp mime_formats("*/*"), do: [:turbo]
  defp mime_formats(_), do: []
end
