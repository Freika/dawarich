defmodule DawarichWeb.Assets do
  @moduledoc false

  def native_path(logical), do: DawarichWeb.Endpoint.static_path("/native/" <> logical)

  def stylesheet_path(logical), do: native_path(logical)

  def stylesheet_path(static, logical) do
    path = "native/" <> logical

    case File.read(Path.join(static, "cache_manifest.json")) do
      {:ok, json} -> "/" <> Map.get(Jason.decode!(json)["latest"], path, path)
      _ -> "/" <> path
    end
  end
end
