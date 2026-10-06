defmodule DawarichWeb.AreaRequest do
  @moduledoc false
  import DawarichWeb.MapWriteRequest, only: [root?: 2, id?: 1]
  import Plug.Conn, only: [get_req_header: 2]

  def target(["areas"]), do: {:area_create, ["POST"], ["POST"]}

  def target(["areas", id]),
    do: if(id?(id), do: {:area_update, ~w(PATCH PUT POST), ~w(PATCH PUT)})

  def target(_), do: nil
  def action(action, _), do: action

  def fields?(action, params) when action in [:area_create, :area_update],
    do:
      root?(params, ~w(name latitude longitude radius)) and
        Enum.all?(params, fn {_, v} -> is_binary(v) end)

  def fields?(_, _), do: false
  def query(%{query_string: ""}), do: {:ok, %{}}
  def query(_), do: :replay

  def format(conn, _) do
    case get_req_header(conn, "accept") do
      [accept] ->
        if String.starts_with?(accept, "text/vnd.turbo-stream.html"),
          do: {:ok, :turbo_stream},
          else: {:ok, :unsupported}

      _ ->
        {:ok, :unsupported}
    end
  end
end
