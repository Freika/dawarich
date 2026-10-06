defmodule DawarichWeb.PlaceRequest do
  @moduledoc false
  import DawarichWeb.A8Request, only: [member: 4, root?: 2]
  @place ~w(name latitude longitude source note tag_ids)

  def target(["places"]), do: {:place_create, ["POST"], "POST"}

  def target(["places", id]),
    do: member(id, :place, ~w(PATCH PUT DELETE POST), ~w(PATCH PUT DELETE))

  def target(_), do: nil

  def action(:place, "DELETE"), do: :place_destroy
  def action(:place, _), do: :place_update
  def action(action, _method), do: action

  def fields?(action, params) when action in [:place_create, :place_update] do
    root?(params, ~w(place)) and
      case params["place"] do
        %{} = map when map_size(map) > 0 ->
          Enum.all?(map, fn
            {"tag_ids", ids} when is_list(ids) -> Enum.all?(ids, &is_binary/1)
            {key, value} -> key in @place and key != "tag_ids" and is_binary(value)
          end)

        _ ->
          false
      end
  end

  def fields?(action, params) when action in [:place_destroy], do: root?(params, [])

  def fields?(_, _), do: false

  def query_keys(:place_destroy), do: ~w(page)
  def query_keys(_), do: []
  def repeated_keys, do: ["place[tag_ids][]"]
end
