defmodule DawarichWeb.SettingsMiscActions do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.Settings.Misc
  alias DawarichWeb.SettingsActions

  def init(action), do: action

  def call(conn, action) do
    methods =
      case action do
        :theme -> ["GET"]
        :changelog_consent -> ["PATCH"]
        :generate_api_key -> ["POST"]
      end

    check = if action == :theme, do: assign(conn, :api_query, %{}), else: conn

    case SettingsActions.admit(check, methods) do
      :ok -> perform(conn, action)
      {:error, status} -> SettingsActions.reject(conn, status)
    end
  rescue
    _ -> SettingsActions.reject(conn, 500)
  end

  defp perform(conn, action) do
    id = conn.assigns.current_user.id

    result =
      case action do
        :theme -> Misc.theme(id, conn.assigns.api_params["theme"])
        :changelog_consent -> Misc.consent(id, conn.assigns.api_params["decision"])
        :generate_api_key -> Misc.rotate(id, conn.assigns.rails_session)
      end

    if result == :ok or match?({:ok, _}, result) do
      case response_format(conn, action) do
        "text/vnd.turbo-stream.html" ->
          conn
          |> put_resp_content_type("text/vnd.turbo-stream.html")
          |> send_resp(200, consent_body(conn))
          |> halt()

        "text/html" ->
          conn
          |> put_resp_header("location", back(conn))
          |> put_resp_content_type("text/html")
          |> send_resp(302, "")
          |> halt()

        nil ->
          SettingsActions.reject(conn, 406)
      end
    else
      SettingsActions.reject(conn, 422)
    end
  end

  defp response_format(conn, :changelog_consent) do
    accept = get_req_header(conn, "accept") |> Enum.join(", ")

    xhr? =
      Enum.any?(get_req_header(conn, "x-requested-with"), &String.match?(&1, ~r/XMLHttpRequest/i))

    case DawarichWeb.PageAccept.formats(accept, xhr?) do
      :invalid_type ->
        nil

      formats ->
        DawarichWeb.PageAccept.negotiate(formats, ~w(text/vnd.turbo-stream.html text/html))
    end
  end

  defp response_format(_conn, _action), do: "text/html"

  defp consent_body(conn) do
    user = Dawarich.Accounts.get(conn.assigns.current_user.id)
    locale = DawarichWeb.Locale.resolve(nil, user, conn.assigns.rails_session)
    csrf = DawarichWeb.RailsCsrf.masked_token(conn.assigns.rails_session)

    navbar =
      Dawarich.Navbar.load(user,
        now: DateTime.utc_now(),
        self_hosted: System.get_env("SELF_HOSTED") == "true"
      )

    for {target, component, attrs} <- [
          {"version-indicator", &DawarichWeb.NavbarParts.version_indicator/1,
           %{version: navbar.version}},
          {"changelog-consent-setting", &DawarichWeb.SettingsParts.consent_card/1,
           %{granted: user.changelog_consent == 1}}
        ],
        into: "" do
      html =
        component.(Map.merge(%{__changed__: %{}, locale: locale, rails_csrf_token: csrf}, attrs))
        |> Phoenix.HTML.Safe.to_iodata()
        |> IO.iodata_to_binary()

      Dawarich.Cable.turbo_tag("replace", target, html)
    end
  end

  defp back(conn), do: DawarichWeb.RailsRedirect.back(conn)
end
