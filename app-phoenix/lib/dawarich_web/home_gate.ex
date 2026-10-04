defmodule DawarichWeb.HomeGate do
  @moduledoc false
  alias Dawarich.Auth.Admission
  alias DawarichWeb.{AdminGate, RailsAuth, Strangler}
  @markers ~w(client aff via referral dawarich_client invitation_token pending_import_ticket)

  def owned?(%{path_info: []} = conn, _params) do
    conn = RailsAuth.call(conn, [])
    query = Plug.Conn.Query.decode(conn.query_string)
    user = conn.assigns.current_user

    keys =
      for part <- String.split(conn.query_string, "&", trim: true),
          do: part |> String.split("=", parts: 2) |> hd() |> URI.decode_www_form()

    "home" not in Application.get_env(:dawarich, :rails_routes, []) and
      conn.method in ["GET", "HEAD"] and is_nil(conn.assigns.rails_locked) and
      (is_nil(user) or AdminGate.supported?(user)) and
      (not is_nil(user) or
         match?(
           {:ok, _},
           DawarichWeb.PublicHomeLive.registration(DawarichWeb.LayoutAssigns.self_hosted?())
         )) and Strangler.page_request?(conn) and
      Admission.headers(conn.req_headers) == :ok and
      Enum.all?(query, fn {_key, value} -> is_binary(value) end) and
      length(keys) == length(Enum.uniq(keys)) and
      not Enum.any?(["_method" | @markers], &Map.has_key?(query, &1)) and
      not Enum.any?(@markers, &Map.has_key?(conn.assigns.rails_session, &1)) and
      Enum.all?(
        ~w(turbo-frame x-dawarich-client x-http-method-override),
        &(Plug.Conn.get_req_header(conn, &1) == [])
      )
  rescue
    _ -> false
  end

  def owned?(_conn, _params), do: false
end
