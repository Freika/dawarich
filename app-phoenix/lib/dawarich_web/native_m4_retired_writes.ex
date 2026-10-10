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
      _ -> false
    end
  end

  def retired?(_), do: false

  def refuse(%{halted: true} = conn), do: conn
  def refuse(conn), do: DawarichWeb.StandaloneError.respond(conn, "not_found", 404)
end
