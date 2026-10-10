defmodule DawarichWeb.NativeM4RetiredWrites do
  @moduledoc false

  def retired?(%{method: method, path_info: path}) when method in ~w(POST PATCH PUT DELETE) do
    case Enum.map(path, &(&1 |> String.split(".", parts: 2) |> hd())) do
      ["imports"] -> true
      ["imports", _] -> true
      ["imports", _, "extraction"] -> true
      ["exports", _] -> true
      ["notifications", _] -> true
      ["settings", "background_jobs"] -> true
      ["family"] -> true
      ["family", "members", _] -> true
      ["family", "invitations"] -> true
      ["family", "invitations", _] -> true
      ["family", "location_requests"] -> true
      ["family", "location_requests", _, action] when action in ~w(accept decline) -> true
      ["family", "location_sharing"] -> true
      ["share_links", type | _] when type in ~w(live timeline shares) -> true
      [type, _, "share_link" | _] when type in ~w(trips tracks) -> true
      ["stats", _, _, "sharing"] -> true
      ["digests", _, "sharing"] -> true
      ["achievements", _, "toggle_sharing"] -> true
      _ -> false
    end
  end

  def retired?(_), do: false

  def refuse(%{halted: true} = conn), do: conn
  def refuse(conn), do: DawarichWeb.RailsErrors.respond(conn, 404)
end
