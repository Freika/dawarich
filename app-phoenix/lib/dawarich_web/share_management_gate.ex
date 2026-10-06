defmodule DawarichWeb.ShareManagementGate do
  @moduledoc false

  import Plug.Conn, only: [get_req_header: 2]
  alias Dawarich.FamilyPageAccess
  alias Dawarich.ShareManagement.{Params, Read}
  alias DawarichWeb.{LayoutAssigns, RailsAuth}

  def mutation?(conn, params) do
    user = RailsAuth.call(conn, []).assigns.current_user

    conn.method in ~w(POST PATCH DELETE) and LayoutAssigns.self_hosted?() and
      get_req_header(conn, "turbo-frame") in [[], ["share-link-modal"]] and
      (is_nil(params["trip_id"]) or params["trip_id"] =~ ~r/\A\d{1,18}\z/) and
      (is_nil(params["id"]) or Dawarich.SharedLinks.canonical?(params["id"])) and
      (is_nil(user) or
         (is_map(user.settings) and
            (is_nil(user.settings["timezone"]) or is_binary(user.settings["timezone"]))))
  end

  def readable_hub?(user, params, now) do
    FamilyPageAccess.validate_settings!(user.settings)
    {:ok, hub} = Read.hub(user, params, now)
    Enum.all?(hub.shares, &renderable?/1)
  rescue
    _error -> false
  end

  def native?(conn, params) do
    query = Plug.Conn.Query.decode(conn.query_string)
    user = RailsAuth.call(conn, []).assigns.current_user

    conn.method in ~w(GET HEAD) and LayoutAssigns.self_hosted?() and
      get_req_header(conn, "turbo-frame") in [[], ["share-link-modal"]] and
      get_req_header(conn, "x-dawarich-client") == [] and
      Enum.all?(query, fn {key, value} ->
        key in ~w(tab start_date end_date) and is_binary(value) and
          (key == "tab" or Params.date_shape?(value))
      end) and
      (is_nil(params["trip_id"]) or params["trip_id"] =~ ~r/\A\d{1,18}\z/) and
      (is_nil(user) or
         (is_map(user.settings) and
            (is_nil(user.settings["timezone"]) or is_binary(user.settings["timezone"])))) and
      readable?(user, conn, params, query)
  end

  defp readable?(nil, _conn, _params, _query), do: true

  defp readable?(user, conn, params, query) do
    FamilyPageAccess.validate_settings!(user.settings)
    now = DateTime.utc_now()

    result =
      cond do
        conn.request_path == "/share_links/hub" -> Read.hub(user, query, now)
        params["trip_id"] -> Read.trip(user, String.to_integer(params["trip_id"]), now)
        true -> Read.live(user, now)
      end

    case result do
      {:ok, %{shares: shares}} -> Enum.all?(shares, &renderable?/1)
      {:ok, %{share: share}} -> is_nil(share) or renderable?(share)
      {:error, 404} -> true
      _ -> false
    end
  end

  defp renderable?(share) do
    is_binary(share.name) and (is_nil(share.magic_phrase) or is_binary(share.magic_phrase)) and
      is_map(share.settings) and
      (share.type != "timeline" or
         Enum.all?(~w(start_date end_date), fn key ->
           is_binary(share.settings[key]) and
             match?({:ok, _}, Date.from_iso8601(share.settings[key]))
         end))
  end
end
