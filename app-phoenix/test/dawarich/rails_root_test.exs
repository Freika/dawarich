defmodule Dawarich.RailsRootTest do
  use ExUnit.Case, async: false

  @tag :tmp_dir
  test "repository file reads use APP_PATH independently of cwd", %{tmp_dir: dir} do
    source_root = Application.fetch_env!(:dawarich, :rails_root)
    keys = ~w(rails_root i18n_path achievements_path app_version_file)a
    previous = Map.new(keys, &{&1, Application.fetch_env(:dawarich, &1)})

    caches = [
      Dawarich.I18n,
      Dawarich.Achievements.Registry,
      DawarichWeb.Assets,
      {DawarichWeb.Assets, :rails_imports}
    ]

    cached = Map.new(caches, &{&1, :persistent_term.get(&1, nil)})
    root = Path.join(dir, "app")
    File.mkdir_p!(Path.join(root, "tmp/phoenix"))
    File.mkdir_p!(Path.join(root, "config"))
    File.write!(Path.join(root, ".app_version"), "1.2.3\n")

    File.write!(
      Path.join(root, "tmp/phoenix/i18n.json"),
      Jason.encode!(%{"en" => %{"release" => "ready"}})
    )

    File.write!(
      Path.join(root, "tmp/phoenix/achievements.json"),
      Jason.encode!(%{
        "definitions" => [],
        "transliteration" => %{"default" => %{}, "rules" => %{}}
      })
    )

    File.write!(
      Path.join(root, "tmp/phoenix/importmap.json"),
      Jason.encode!(%{"imports" => %{"release" => "/assets/release.js"}})
    )

    File.write!(
      Path.join(root, "config/sprockets-manifest.json"),
      Jason.encode!(%{"assets" => %{"release.css" => "release-123.css"}})
    )

    app_path = System.get_env("APP_PATH")
    for key <- keys, do: Application.delete_env(:dawarich, key)
    for key <- caches, do: :persistent_term.erase(key)
    System.put_env("APP_PATH", root)

    on_exit(fn ->
      for {key, value} <- previous do
        case value do
          {:ok, value} -> Application.put_env(:dawarich, key, value)
          :error -> Application.delete_env(:dawarich, key)
        end
      end

      for {key, value} <- cached do
        if value, do: :persistent_term.put(key, value), else: :persistent_term.erase(key)
      end

      if app_path, do: System.put_env("APP_PATH", app_path), else: System.delete_env("APP_PATH")
    end)

    File.cd!(dir, fn ->
      assert Dawarich.RailsRoot.join("public/404.html") == Path.join(root, "public/404.html")
      assert Dawarich.Build.root() == root
      assert DawarichWeb.PublicFiles.boot_config().root == Path.join(root, "public")
      assert Dawarich.Storage.config!(%{}).root == Path.join(root, "storage")

      assert Dawarich.Storage.services!(%{}).services["test"].root ==
               Path.join(root, "tmp/storage")

      assert Dawarich.AppVersion.current() == "1.2.3"
      assert Dawarich.I18n.t("en", "release") == {:ok, "ready"}
      assert Dawarich.Achievements.Registry.all() == []
      assert DawarichWeb.Assets.stylesheet_path("release.css") == "/assets/release-123.css"
      assert DawarichWeb.Assets.rails_imports() == %{"release" => "/assets/release.js"}
      Application.put_env(:dawarich, :rails_root, source_root)
      assert Dawarich.RailsRoot.root() == source_root
      Application.delete_env(:dawarich, :rails_root)
      System.delete_env("APP_PATH")
      assert Dawarich.RailsRoot.root() == source_root
    end)
  end
end
