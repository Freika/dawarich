defmodule DawarichWeb.MapTagRequest do
  @moduledoc false
  import Plug.Conn, only: [get_req_header: 2]
  import DawarichWeb.MapWriteRequest, only: [root?: 2, nested?: 2, id?: 1]
  @tag ~w(name icon color privacy_radius_meters)

  def target(["tags"]), do: {:tag_create, ["POST"], ["POST"]}

  def target(["tags", id]),
    do: if(id?(id), do: {:tag_member, ~w(PATCH PUT DELETE POST), ~w(PATCH PUT DELETE)})

  def target(_), do: nil
  def action(:tag_member, "DELETE"), do: :tag_destroy
  def action(:tag_member, _), do: :tag_update

  def action(action, _), do: action

  def fields?(action, params) when action in [:tag_create, :tag_update],
    do: root?(params, ["tag"]) and nested?(params["tag"], @tag)

  def fields?(:tag_destroy, params), do: root?(params, [])

  def fields?(_, _), do: false
  def query(%{query_string: ""}), do: {:ok, %{}}
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
