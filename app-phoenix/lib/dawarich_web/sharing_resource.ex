defmodule DawarichWeb.SharingResource do
  @moduledoc false
  def from(path, owner, params) do
    resource =
      case String.split(path, "/", trim: true) do
        ["share_links", "hub"] ->
          %{type: :hub}

        ["share_links", "live", "new"] ->
          %{type: :live}

        ["share_links", "timeline", "new"] ->
          %{type: :timeline}

        ["trips", id, "share_link", "new"] ->
          %{type: :trip, id: number(id)}

        ["tracks", id, "share_link", "new"] ->
          %{type: :track, id: number(id)}

        ["stats", year, month, "sharing"] ->
          %{type: :month, year: number(year), month: number(month)}

        ["digests", year, "sharing"] ->
          %{type: :digest, year: number(year)}

        ["achievements", key, "sharing"] ->
          %{type: :achievement, key: key}

        _ ->
          nil
      end

    if resource,
      do: {:ok, Map.put(resource, :owner_id, owner), tab(params)},
      else: {:error, :not_found}
  end

  def tab(%{"tab" => tab}) when tab in ~w(live timeline make shared), do: tab
  def tab(_), do: "live"

  def selected(%{type: :hub} = resource, tab) when tab in ~w(live timeline),
    do: %{resource | type: if(tab == "live", do: :live, else: :timeline)}

  def selected(resource, _), do: resource

  defp number(raw) when is_binary(raw) and byte_size(raw) <= 19 do
    case Integer.parse(raw) do
      {id, ""} when id > 0 and id <= 9_223_372_036_854_775_807 -> id
      _ -> nil
    end
  end

  defp number(_), do: nil

  def back(%{type: :trip, id: id}), do: "/trips/#{id}"
  def back(%{type: :track, id: id}), do: "/tracks/#{id}"
  def back(%{type: :month, year: year, month: month}), do: "/stats/#{year}/#{month}"
  def back(%{type: :digest, year: year}), do: "/digests/#{year}"
  def back(%{type: :achievement, key: key}), do: "/achievements/#{key}"
  def back(_), do: "/map/v2"
end
