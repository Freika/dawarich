defmodule DawarichWeb.Assets do
  @moduledoc false

  @family_page_js Path.expand("../../priv/static/js/family_page.js", __DIR__)
  @external_resource @family_page_js
  @family_page_hash @family_page_js
                    |> File.read!()
                    |> then(&:crypto.hash(:md5, &1))
                    |> Base.url_encode64(padding: false)

  @app_js Path.expand("../../priv/static/js/app.js", __DIR__)
  @external_resource @app_js
  @app_hash @app_js
            |> File.read!()
            |> then(&:crypto.hash(:md5, &1))
            |> Base.url_encode64(padding: false)

  @map_shell_js Path.expand("../../priv/static/js/map_shell.js", __DIR__)
  @external_resource @map_shell_js
  @map_shell_hash @map_shell_js
                  |> File.read!()
                  |> then(&:crypto.hash(:md5, &1))
                  |> Base.url_encode64(padding: false)

  @rails_bridge_js Path.expand("../../priv/static/js/rails_bridge.js", __DIR__)
  @external_resource @rails_bridge_js
  @rails_bridge_hash @rails_bridge_js
                     |> File.read!()
                     |> then(&:crypto.hash(:md5, &1))
                     |> Base.url_encode64(padding: false)

  def stylesheet_path(logical), do: "/assets/" <> Map.get(manifest(), logical, logical)

  def stylesheet_path(rails_root, logical),
    do: "/assets/" <> Map.get(read_manifest(rails_root), logical, logical)

  def script_versions do
    %{
      phoenix: to_string(Application.spec(:phoenix, :vsn)),
      live_view: to_string(Application.spec(:phoenix_live_view, :vsn)),
      app: @app_hash,
      map_shell: @map_shell_hash,
      rails_bridge: @rails_bridge_hash,
      family_page: @family_page_hash
    }
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
      nil -> tap(read_manifest(File.cwd!()), &:persistent_term.put(__MODULE__, &1))
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
