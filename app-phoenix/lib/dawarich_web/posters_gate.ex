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
      if format(conn, conn.assigns.api_params) == :json do
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
    accept = get_req_header(conn, "accept") |> Enum.join(",")

    cond do
      params["format"] == "json" ->
        :json

      params["format"] == "turbo_stream" ->
        :turbo

      params["format"] == "html" ->
        :html

      params["format"] not in [nil, ""] ->
        :other

      String.contains?(accept, "text/vnd.turbo-stream.html") ->
        :turbo

      String.contains?(accept, "application/json") ->
        :json

      accept == "" and Body.kind(conn) == :json ->
        :json

      accept == "" or String.contains?(accept, "text/html") or String.contains?(accept, "*/*") or
          DawarichWeb.Strangler.browser_like?(accept) ->
        :html

      true ->
        :other
    end
  end
end
