defmodule DawarichWeb.AchievementPageGate do
  @moduledoc false
  @allowed_params ~w(q status page locale commit)
  @last_page 1_000_000_000_000

  def open?(conn, path_params) do
    params = Plug.Conn.Query.decode(conn.query_string)

    authenticated?(conn) and Enum.all?(params, &allowed?/1) and
      match?({:ok, _}, Dawarich.Achievements.Collection.route(path_params["key"]))
  end

  defp allowed?({"page", value}),
    do: is_binary(value) and DawarichWeb.Params.ruby_to_i(value) <= @last_page

  defp allowed?({key, value}), do: key in @allowed_params and is_binary(value)
  defp authenticated?(conn), do: not is_nil(DawarichWeb.RailsAuth.user_id(conn))
end
