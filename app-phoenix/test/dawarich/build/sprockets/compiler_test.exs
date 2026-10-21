defmodule Dawarich.Build.Sprockets.CompilerTest do
  use ExUnit.Case, async: true

  alias Dawarich.Build
  alias Dawarich.Build.Sprockets.{Compiler, Env}

  @vectors %{
    "turbo.min.js" =>
      "turbo.min-b86d83036ff04169e5bf3ebbc82e0ad528456259e47091b448f41a3cadabdb40.js",
    "turbo.min.js.map" =>
      "turbo.min.js-c6732dc7c1683ff78fbfb710f7dda227e58db136b253b8d07628207a5ccdb6b7.map",
    "stimulus.min.js" =>
      "stimulus.min-dd364f16ec9504dfb72672295637a1c8838773b01c0b441bd41008124c407894.js",
    "stimulus-loading.js" =>
      "stimulus-loading-3576ce92b149ad5d6959438c6f291e2426c86df3b874c525b30faad51b0d96b3.js",
    "pmtiles.js" => "pmtiles-96ae87810e130ad54507f0ab9939dddcb1e4f951562459cb579ad65fd136a7eb.js",
    "inter-font.css" =>
      "inter-font-8c3e82affb176f4bca9616b838d906343d1251adc8408efe02cf2b1e4fcf2bc4.css",
    "trix.css" => "trix-27b67936197943926cb14d19903e2a81f4ed2cb745aec0e8f198e70ddf292774.css",
    "actiontext.css" =>
      "actiontext-7c6127c5682cea9debf5454351dae886079b68330ba4f5299bd31d4de53a761b.css",
    "favicon/browserconfig.xml" =>
      "favicon/browserconfig-a051798f849643140d9d5c67f97052379abd40a2d6861edcb41aa461288151e9.xml",
    "favicon/browserconfig.xml.erb" =>
      "favicon/browserconfig.xml-6069beda5a8a76a9bcaa2bb83d0e43cd357001e707ad4de5b4f7c3360624e688.erb"
  }

  test "vendored and app assets compile to the digests Rails' Sprockets produced" do
    root = Build.root()
    env = Env.new(root)

    for {logical, expected} <- @vectors do
      {result, _cache} = Compiler.build(env, Env.resolve(env, logical, nil, root), %{})
      assert result.digest_path == expected, logical
    end
  end

  test "inter-font.css links the sixteen vendored Inter fonts" do
    root = Build.root()
    env = Env.new(root)
    {result, _cache} = Compiler.build(env, Env.resolve(env, "inter-font.css", nil, root), %{})

    assert result.links
           |> Enum.map(& &1.logical)
           |> Enum.count(&String.starts_with?(&1, "Inter-")) == 16
  end

  @tag :tmp_dir
  test "require_tree bundles in Sprockets' post-order, honouring stub and require_self", %{
    tmp_dir: root
  } do
    sheets = %{
      "a.css" => "/*\n *= require_tree .\n *= stub c\n *= require_self\n */\n.a{}\n",
      "b.css" => "/*\n *= require d\n */\n.b{}\n",
      "c.css" => ".c{}\n",
      "d.css" => ".d{}\n",
      "sub/e.css" => ".e{}\n"
    }

    for {name, body} <- sheets do
      path = Path.join([root, "app/assets/stylesheets", name])
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, body)
    end

    env = Env.new(root)
    {result, _cache} = Compiler.build(env, Env.resolve(env, "a.css", nil, root), %{})

    assert result.source == ".d{}\n/*\n\n */\n.b{}\n.e{}\n/*\n\n\n\n */\n.a{}\n"
  end

  test "the closure of the precompile list holds Rails' extra roots and links" do
    logicals = Build.root() |> Compiler.compile() |> Enum.map(& &1.logical)

    for logical <-
          ~w(manifest.js favicon/browserconfig.xml.erb Inter-roman.latin.var.woff2 stimulus-importmap-autoloader.js inter-font.css activestorage.js tailwind.css),
        do: assert(logical in logicals, logical)

    refute Enum.any?(logicals, &String.starts_with?(&1, "icons/"))
  end
end
