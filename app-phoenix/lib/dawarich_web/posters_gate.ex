defmodule DawarichWeb.PostersGate do
  @moduledoc false
  import Plug.Conn, only: [get_req_header: 2]

  def native?(conn, params) do
    conn.method in ~w(POST DELETE) and DawarichWeb.LayoutAssigns.self_hosted?() and
      get_req_header(conn, "turbo-frame") == [] and
      (is_nil(params["id"]) or params["id"] =~ ~r/\A[1-9]\d{0,17}\z/) and
      owned_delete?(conn, params)
  end

  defp owned_delete?(%{method: "DELETE"} = conn, params) do
    case DawarichWeb.RailsAuth.call(conn, []).assigns.current_user do
      nil -> true
      user -> not is_nil(Dawarich.MapGallery.poster(user.id, String.to_integer(params["id"])))
    end
  end

  defp owned_delete?(_, _), do: true

  def supported?(conn, params) do
    accept = get_req_header(conn, "accept") |> Enum.join(",")

    types =
      for entry <- String.split(accept, ","),
          do: entry |> String.split(";") |> hd() |> String.trim()

    (accept == "" or DawarichWeb.Strangler.browser_like?(accept) or
       Enum.all?(
         types,
         &(&1 in ~w(text/html */* application/xhtml+xml text/vnd.turbo-stream.html))
       )) and
      Enum.all?(params, fn {key, value} ->
        (key in ~w(authenticity_token commit) and is_binary(value)) or
          (conn.method == "POST" and key == "poster" and is_map(value) and
             Enum.all?(value, fn {_, item} -> is_binary(item) end))
      end)
  end
end
