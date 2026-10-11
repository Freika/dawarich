defmodule DawarichWeb.Assets do
  @moduledoc false

  def native_path(logical), do: DawarichWeb.Endpoint.static_path("/native/" <> logical)

  def stylesheet_path(logical), do: "/assets/" <> Map.get(manifest(), logical, logical)

  def stylesheet_path(rails_root, logical),
    do: "/assets/" <> Map.get(read_manifest(rails_root), logical, logical)

  def asset_path(rails_root, logical) do
    assets = read_manifest(rails_root)

    Enum.find_value([logical, logical <> ".js", logical <> "/index.js"], fn candidate ->
      if digest = assets[candidate], do: "/assets/" <> digest
    end)
  end

  def rails_imports do
    case :persistent_term.get({__MODULE__, :rails_imports}, nil) do
      nil ->
        tap(
          read_imports(Dawarich.RailsRoot.join("tmp/phoenix/importmap.json")),
          &:persistent_term.put({__MODULE__, :rails_imports}, &1)
        )

      imports ->
        imports
    end
  end

  def read_imports(path) do
    with {:ok, json} <- File.read(path),
         {:ok, %{"imports" => %{} = imports}} <- Jason.decode(json) do
      imports
    else
      _ -> %{}
    end
  end

  defp manifest do
    case :persistent_term.get(__MODULE__, nil) do
      nil -> tap(read_manifest(Dawarich.RailsRoot.root()), &:persistent_term.put(__MODULE__, &1))
      assets -> assets
    end
  end

  defp read_manifest(rails_root) do
    configured = Path.join(rails_root, "config/sprockets-manifest.json")

    legacy =
      rails_root
      |> Path.join("public/assets/.sprockets-manifest-*.json")
      |> Path.wildcard(match_dot: true)

    with path when is_binary(path) <- Enum.find([configured | legacy], &File.regular?/1),
         {:ok, json} <- File.read(path),
         {:ok, %{"assets" => assets}} <- Jason.decode(json) do
      assets
    else
      _ -> %{}
    end
  end
end
