defmodule Dawarich.Build.Sprockets.EnvTest do
  use ExUnit.Case, async: true

  alias Dawarich.Build.Sprockets.Env

  @moduletag :tmp_dir

  defp file!(root, path) do
    full = Path.join(root, path)
    File.mkdir_p!(Path.dirname(full))
    File.write!(full, "x")
  end

  test "load paths follow Rails: app/assets/*, lib/assets/*, vendor/assets/*, app/javascript, vendor/javascript",
       %{tmp_dir: root} do
    for dir <-
          ~w(app/assets/stylesheets app/assets/builds app/assets/.hidden vendor/assets/javascripts app/javascript vendor/javascript),
        do: File.mkdir_p!(Path.join(root, dir))

    assert Env.new(root).paths ==
             Enum.map(
               ~w(app/assets/builds app/assets/stylesheets vendor/assets/javascripts app/javascript vendor/javascript),
               &Path.join(root, &1)
             )
  end

  test "resolves logical paths in load-path order, extensionless names by type, ERB twins rendered",
       %{tmp_dir: root} do
    file!(root, "app/assets/images/favicon/browserconfig.xml.erb")
    file!(root, "vendor/assets/javascripts/activestorage.js")
    file!(root, "vendor/assets/javascripts/activestorage.esm.js")
    file!(root, "vendor/assets/stylesheets/trix.css")
    file!(root, "app/assets/stylesheets/trix.css")
    env = Env.new(root)

    assert %{logical: "favicon/browserconfig.xml", kind: :xml, erb: true} =
             Env.resolve(env, "favicon/browserconfig.xml", nil, root)

    assert %{logical: "favicon/browserconfig.xml.erb", kind: :raw, erb: false} =
             Env.resolve(env, "favicon/browserconfig.xml.erb", nil, root)

    assert %{logical: "activestorage.js", kind: :js} =
             Env.resolve(env, "activestorage", nil, root)

    assert %{logical: "activestorage.esm.js", kind: :js} =
             Env.resolve(env, "activestorage.esm", nil, root)

    assert Env.resolve(env, "trix", :css, root).file ==
             Path.join(root, "app/assets/stylesheets/trix.css")

    assert Env.resolve(env, "missing.png", nil, root) == nil
    assert Env.resolve(env, "favicon/../activestorage.js", nil, root) == nil
  end

  test "trees list entries Sprockets' way: hidden names skipped, a directory sorted as name/",
       %{tmp_dir: root} do
    for f <- ~w(s/a.css s/a-b.css s/a/z.css s/.keep s/b~ s/#c#), do: file!(root, f)
    dir = Path.join(root, "s")

    assert dir |> Env.tree(true) |> Enum.map(&Path.relative_to(&1, dir)) ==
             ~w(a-b.css a.css a a/z.css)
  end
end
