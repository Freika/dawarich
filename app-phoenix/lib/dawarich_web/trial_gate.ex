defmodule DawarichWeb.TrialGate do
  @moduledoc false
  alias Dawarich.Auth.Admission
  alias DawarichWeb.{AdminGate, LayoutAssigns, RailsAuth, Strangler}
  @markers ~w(client aff via referral dawarich_client invitation_token pending_import_ticket)

  def upgrade?(conn, _params) do
    conn = RailsAuth.call(conn, [])
    user = conn.assigns.current_user

    request?(conn) and (is_nil(user) or AdminGate.supported?(user)) and
      (Dawarich.Standalone.enabled?() or is_nil(user) or LayoutAssigns.self_hosted?() or
         checkout_configured?())
  rescue
    _ -> false
  end

  def resume?(conn, _params) do
    conn = RailsAuth.call(conn, [])
    user = conn.assigns.current_user

    request?(conn) and (is_nil(user) or AdminGate.supported?(user)) and
      (Dawarich.Standalone.enabled?() or is_nil(user) or user.status != 3 or
         checkout_configured?())
  rescue
    _ -> false
  end

  defp request?(conn) do
    query = Plug.Conn.Query.decode(conn.query_string)

    keys =
      for part <- String.split(conn.query_string, "&", trim: true),
          do: part |> String.split("=", parts: 2) |> hd() |> URI.decode_www_form()

    conn.method in ["GET", "HEAD"] and Strangler.page_request?(conn) and
      Admission.headers(conn.req_headers) == :ok and length(keys) == length(Enum.uniq(keys)) and
      Enum.all?(query, fn {key, value} ->
        is_binary(value) or (key in ["plan", "interval"] and (is_list(value) or is_map(value)))
      end) and
      not Map.has_key?(query, "_method") and
      (Dawarich.Standalone.enabled?() or
         (not Enum.any?(@markers, &Map.has_key?(query, &1)) and
            not Enum.any?(@markers, &Map.has_key?(conn.assigns.rails_session, &1)))) and
      (Dawarich.Standalone.enabled?() or Plug.Conn.get_req_header(conn, "x-dawarich-client") == []) and
      Enum.all?(
        ~w(turbo-frame x-http-method-override),
        &(Plug.Conn.get_req_header(conn, &1) == [])
      )
  end

  def checkout_configured? do
    uri = URI.parse(System.get_env("MANAGER_URL", ""))

    uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.host != "" and
      is_nil(uri.userinfo) and is_nil(uri.query) and is_nil(uri.fragment) and
      is_binary(System.get_env("JWT_SECRET_KEY")) and System.get_env("JWT_SECRET_KEY") != ""
  end
end
