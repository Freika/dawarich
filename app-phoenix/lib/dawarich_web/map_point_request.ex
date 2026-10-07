defmodule DawarichWeb.MapPointRequest do
  @moduledoc false
  import Plug.Conn, only: [get_req_header: 2]
  alias DawarichWeb.Api.Body
  import DawarichWeb.MapWriteRequest, only: [root?: 2]
  @filters ~w(start_at end_at order_by import_id)

  def target(["points", "bulk_destroy"]), do: {:point_destroy, ~w(DELETE POST), ["DELETE"]}

  def target(_), do: nil

  def fields?(:point_destroy, params) do
    root?(params, ["point_ids", "page" | @filters]) and
      Enum.all?(params, fn
        {"point_ids", ids} when is_list(ids) -> Enum.all?(ids, &is_binary/1)
        {_, value} -> is_binary(value)
      end)
  end

  def fields?(_, _), do: false

  def action(action, _), do: action

  def query(%{query_string: ""}), do: {:ok, %{}}

  def query(%{path_info: ["points", "bulk_destroy"], query_string: raw}) do
    with false <- Regex.match?(~r/%(?![0-9A-Fa-f]{2})/, raw),
         {:ok, pairs} <- Body.segments(raw),
         true <-
           Enum.all?(pairs, fn
             {"controller", value} -> value == "points"
             {"action", value} -> value == "index"
             {key, value} -> key in ["page", "commit" | @filters] and is_binary(value)
           end),
         true <- length(pairs) == length(Enum.uniq_by(pairs, &elem(&1, 0))) do
      {:ok, Map.new(pairs)}
    else
      _ -> :replay
    end
  end

  def query(_), do: :replay

  def format(conn, action) do
    case get_req_header(conn, "accept") do
      [accept] -> negotiate(accept, action)
      [] when action in [:tag_create, :tag_update, :tag_destroy] -> {:ok, :html}
      _ -> :replay
    end
  end

  defp negotiate(accept, :segment_update) do
    case accept do
      "*/*" -> {:ok, :turbo_stream}
      "text/html;q=0.5, text/vnd.turbo-stream.html;q=1" -> {:ok, :turbo_stream}
      "text/vnd.turbo-stream.html;q=0.5, text/html;q=1" -> {:ok, :html}
      _ -> types(accept, :segment_update)
    end
  end

  defp negotiate(accept, action)
       when action in [:tag_create, :tag_update, :tag_destroy, :point_destroy] do
    if String.trim(accept) in ["", "*/*"] or DawarichWeb.Strangler.browser_like?(accept) do
      {:ok, :html}
    else
      types(accept, action)
    end
  end

  defp negotiate(accept, action), do: types(accept, action)

  defp types(accept, action) do
    types = accept |> String.split(",") |> Enum.map(&String.trim/1)
    allowed = ~w(text/html application/xhtml+xml text/vnd.turbo-stream.html)

    if types != [] and Enum.all?(types, &(&1 in allowed)) do
      cond do
        action == :segment_update ->
          {:ok, if(hd(types) == "text/vnd.turbo-stream.html", do: :turbo_stream, else: :html)}

        "text/html" in types ->
          {:ok, :html}

        true ->
          :replay
      end
    else
      :replay
    end
  end
end
