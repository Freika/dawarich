defmodule DawarichWeb.StandaloneSettings do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.{Repo, TimeZoneName, TimeZoneOptions}
  alias DawarichWeb.{RailsForm, RailsSession, RequestURL, StandaloneError, Translate}

  @boolean ~w(monthly_digest_emails_enabled yearly_digest_emails_enabled news_emails_enabled show_supporter_badge)
  @keys ~w(authenticity_token _method commit utf8 timezone locale supporter_email supporter_github_username) ++
          @boolean
  @false_values ~w(0 f F false FALSE off OFF)

  def enabled?(_conn, _params), do: Dawarich.Standalone.enabled?()
  def init(opts), do: opts

  def call(conn, _opts) do
    params = conn.assigns.api_params
    check = assign(conn, :api_params, Map.delete(params, "locale"))

    with true <- conn.assigns.api_query == %{},
         true <- Enum.all?(params, fn {key, value} -> key in @keys and is_binary(value) end),
         true <- conn.method != "POST" or params["_method"] == "patch",
         :ok <- RailsForm.admission(check, allowed_overrides: ["PATCH"]) do
      save(conn, params)
    else
      _ -> StandaloneError.respond(conn, "standalone_settings_envelope", 422)
    end
  rescue
    _ -> StandaloneError.respond(conn, "standalone_settings_failure", 500)
  end

  defp save(conn, params) do
    changes = Map.take(params, ~w(supporter_email supporter_github_username))

    changes =
      if params["locale"] in DawarichWeb.Locale.locales(),
        do: Map.put(changes, "locale", params["locale"]),
        else: changes

    zone = TimeZoneName.to_iana(params["timezone"] || "")

    changes =
      if Enum.any?(TimeZoneOptions.list(), fn {_, iana} -> iana == zone end),
        do: Map.put(changes, "timezone", params["timezone"]),
        else: changes

    changes =
      Enum.reduce(@boolean, changes, fn key, acc ->
        if Map.has_key?(params, key),
          do: Map.put(acc, key, params[key] != "" and params[key] not in @false_values),
          else: acc
      end)

    digest =
      Enum.any?(
        ~w(monthly_digest_emails_enabled yearly_digest_emails_enabled),
        &Map.has_key?(changes, &1)
      )

    Repo.query!(
      """
      UPDATE users SET settings =
        (CASE WHEN jsonb_typeof(settings) = 'object' THEN settings ELSE '{}'::jsonb END || $2::jsonb)
        - CASE WHEN $3 THEN 'digest_emails_enabled' ELSE '' END, updated_at = NOW() WHERE id = $1
      """,
      [conn.assigns.current_user.id, changes, digest],
      log: false
    )

    locale = changes["locale"] || conn.assigns.current_user.settings["locale"] || "en"
    notice = Translate.t(locale, "controllers.settings.general.settings_updated", %{})

    conn
    |> RailsSession.stage(%{"flash" => %{"discard" => [], "flashes" => %{"notice" => notice}}})
    |> put_resp_header("location", RequestURL.base(conn) <> "/settings/general")
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_content_type("text/html")
    |> send_resp(302, "")
    |> halt()
  end
end
