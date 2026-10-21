defmodule DawarichWeb.RouteVideoRequest do
  @moduledoc false
  import DawarichWeb.A8Request, only: [member: 4, root?: 2]

  def target(["route_videos"]), do: {:video_create, ["POST"], "POST"}
  def target(["route_videos", id]), do: member(id, :video_destroy, ["DELETE", "POST"], "DELETE")
  def target(_), do: nil

  def action(action, _method), do: action

  def decode(pairs) do
    %Jason.OrderedObject{values: roots} =
      DawarichWeb.Api.SourceParams.from_pairs(pairs, ordered: true)

    Map.new(roots, fn
      {"route_video", %Jason.OrderedObject{values: fields}} ->
        video =
          for {key, value} <- fields,
              key in ~w(name file),
              is_binary(value),
              into: %{},
              do: {key, value}

        video =
          case List.keyfind(fields, "settings", 0) do
            {"settings", %Jason.OrderedObject{values: settings}} ->
              Map.put(video, "settings", Map.new(settings))

            _ ->
              video
          end

        {"route_video", video}

      {key, value} ->
        {key, DawarichWeb.Api.SourceParams.munge(value)}
    end)
  catch
    :bad_request -> raise ArgumentError
  end

  def fields?(:video_create, params) do
    root?(params, ~w(route_video)) and
      case params["route_video"] do
        %{"file" => file} = video when is_binary(file) ->
          Enum.all?(video, fn
            {"settings", %{} = _settings} -> true
            {key, value} -> key in ~w(name file) and is_binary(value)
          end)

        _ ->
          false
      end
  end

  def fields?(action, params) when action in [:video_destroy], do: root?(params, [])

  def fields?(_, _), do: false

  def query_keys(:video_destroy), do: ["_method"]
  def query_keys(_), do: []
  def repeated_keys, do: ["visit_ids[]"]
end
