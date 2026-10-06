defmodule DawarichWeb.AdminGate do
  @moduledoc false

  alias Dawarich.Admin.{InstancePage, UsersPage}
  alias Dawarich.Auth.Admission
  alias Dawarich.{Repo, TripSettings, UserTimeZone}
  alias DawarichWeb.{LayoutAssigns, RailsAuth, Strangler}

  @markers ~w(client aff via referral dawarich_client invitation_token pending_import_ticket)

  def instance?(conn, _params) do
    eligible?(conn, :admin) and match?({:ok, _}, InstancePage.load(Repo, System.get_env()))
  rescue
    _ -> false
  end

  def users?(conn, params) do
    eligible?(conn, :admin) and users_state?(conn, params)
  rescue
    _ -> false
  end

  def background?(conn, _params), do: eligible?(conn, :background)

  def supported?(%{settings: settings}) when is_map(settings) do
    case TripSettings.read(settings) do
      {:ok, _} ->
        zone = settings["timezone"] || System.get_env("TIME_ZONE", "Europe/Berlin")
        TripSettings.zone?(%{"timezone" => zone}, UserTimeZone.name(settings))

      _ ->
        false
    end
  rescue
    _ -> false
  end

  def supported?(_), do: false

  defp eligible?(conn, mode) do
    query = Plug.Conn.Query.decode(conn.query_string)
    conn = RailsAuth.call(conn, [])
    user = conn.assigns.current_user

    (LayoutAssigns.self_hosted?() or
       (mode == :background and DawarichWeb.OperatorRedirect.operator?(user))) and
      not is_nil(user) and
      (mode == :background or user.admin == true) and supported?(user) and
      Strangler.page_request?(conn) and Admission.headers(conn.req_headers) == :ok and
      conn.method in ["GET", "HEAD"] and
      Enum.all?(query, fn {_key, value} -> is_binary(value) end) and
      not Enum.any?(["_method" | @markers], &Map.has_key?(query, &1)) and
      not Enum.any?(@markers, &Map.has_key?(conn.assigns.rails_session, &1)) and
      Enum.all?(
        ~w(turbo-frame x-dawarich-client x-http-method-override),
        &(Plug.Conn.get_req_header(conn, &1) == [])
      ) and
      unique_query?(conn.query_string)
  rescue
    _ -> false
  end

  defp unique_query?(query) do
    keys =
      for segment <- String.split(query, "&", trim: true),
          do: segment |> String.split("=", parts: 2) |> hd() |> URI.decode_www_form()

    length(keys) == length(Enum.uniq(keys))
  end

  defp users_state?(conn, %{"id" => id}) when is_binary(id) do
    if String.length(id) <= 18 and id =~ ~r/\A[1-9][0-9]*\z/ do
      user = RailsAuth.call(conn, []).assigns.current_user
      kind = if String.ends_with?(conn.request_path, "/edit"), do: :edit, else: :show
      match?({:ok, _}, UsersPage.find(user, String.to_integer(id), kind))
    else
      false
    end
  end

  defp users_state?(conn, params) do
    if Map.has_key?(params, "id") do
      false
    else
      user = RailsAuth.call(conn, []).assigns.current_user
      match?({:ok, _}, UsersPage.list(user, Plug.Conn.Query.decode(conn.query_string)))
    end
  end
end
