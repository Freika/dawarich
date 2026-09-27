defmodule DawarichWeb.Assets do
  @moduledoc false

  @app_js Path.expand("../../priv/static/js/app.js", __DIR__)
  @external_resource @app_js
  @app_hash @app_js
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
      app: @app_hash
    }
  end

  defp manifest do
    case :persistent_term.get(__MODULE__, nil) do
      nil -> tap(read_manifest(File.cwd!()), &:persistent_term.put(__MODULE__, &1))
      assets -> assets
    end
  end

  defp read_manifest(rails_root) do
    with [path | _] <-
           rails_root
           |> Path.join("public/assets/.sprockets-manifest-*.json")
           |> Path.wildcard(match_dot: true),
         {:ok, json} <- File.read(path),
         {:ok, %{"assets" => assets}} <- Jason.decode(json) do
      assets
    else
      _ -> %{}
    end
  end
end
