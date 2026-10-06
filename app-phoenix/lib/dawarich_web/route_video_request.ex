defmodule DawarichWeb.RouteVideoRequest do
  @moduledoc false
  import DawarichWeb.A8Request, only: [member: 4, root?: 2, scalar_map?: 1]

  def target(["route_videos"]), do: {:video_create, ["POST"], "POST"}
  def target(["route_videos", id]), do: member(id, :video_destroy, ["DELETE", "POST"], "DELETE")
  def target(_), do: nil

  def action(action, _method), do: action

  def fields?(:video_create, params) do
    root?(params, ~w(route_video)) and
      case params["route_video"] do
        %{"file" => file} = video when is_binary(file) ->
          Enum.all?(video, fn
            {"settings", %{} = settings} -> scalar_map?(settings)
            {key, value} -> key in ~w(name file) and is_binary(value)
          end)

        _ ->
          false
      end
  end

  def fields?(action, params) when action in [:video_destroy], do: root?(params, [])

  def fields?(_, _), do: false

  def query_keys(_), do: []
  def repeated_keys, do: ["visit_ids[]"]
end
