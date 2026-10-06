defmodule Dawarich.Build.DockerfileTest do
  use ExUnit.Case, async: true

  @css "app/assets/builds/tailwind.css"

  defp stages do
    Path.expand("../../../../docker/Dockerfile", __DIR__)
    |> File.read!()
    |> String.replace(~r/\\\n/, " ")
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
    |> Enum.reduce([], fn
      "FROM " <> rest, acc ->
        name = with [_, name] <- Regex.run(~r/ AS (\S+)$/i, rest), do: name
        [{name, []} | acc]

      line, [{name, lines} | acc] ->
        [{name, lines ++ [line]} | acc]
    end)
    |> Enum.reverse()
  end

  defp native_stage do
    stage = List.keyfind(stages(), "native_runtime", 0)
    assert stage, "the opt-in native_runtime target is missing"
    elem(stage, 1)
  end

  @tag :a12f4_b01_1
  test "final image recipe uses trixie and no Ruby runtime or gem toolchain" do
    native = Enum.join(native_stage(), "\n")
    recipe = File.read!(Path.expand("../../../../docker/Dockerfile", __DIR__))
    assert recipe =~ "FROM debian:trixie-slim AS native_runtime"
    assert native =~ "erlang-base erlang-inets erlang-ssl erlang-xmerl"
    assert native =~ "postgresql-client"
    assert native =~ "ca-certificates"
    assert native =~ "tzdata"
    assert native =~ "gosu"
    assert native =~ "procps"
    assert native =~ "libegl1 libgles2 libgbm1 libglx0 libopengl0"
    assert native =~ "COPY --from=mbgl_libs /out /opt/mbgl-libs"
    assert native =~ ~s|test "$(node -p 'process.versions.modules')" = 115|
    assert native =~ ~s(ENTRYPOINT ["web-entrypoint.sh"])
    refute native =~ ~r/BUNDLE_|GEM_|RUBY_|jemalloc|ld\.so\.preload/
    refute native =~ ~r/\b(?:gem|bundle) (?:install|update|exec)/
    refute native =~ ~r/build-essential|cmake|(?:lib\S+)-dev|\b(?:npm|yarn|git)\b/
    assert elem(List.last(stages()), 0) != "native_runtime"
    assert List.last(stages()) |> elem(1) |> List.last() == ~s(ENTRYPOINT [ "bundle", "exec" ])
  end

  @tag :a12f4_b02_1
  test "explicit image payload includes unchanged OpenAPI and local Swagger assets" do
    native = native_stage()
    assert "COPY swagger/v1/swagger.yaml swagger/v1/swagger.yaml" in native
    assert "COPY --from=phoenix_builder /out/public/api-docs public/api-docs" in native

    {"phoenix_builder", builder} = List.keyfind(stages(), "phoenix_builder", 0)
    swagger = Enum.find(builder, &String.contains?(&1, "mkdir -p /out/public/api-docs"))
    assert swagger

    for asset <- ~w(swagger-ui-bundle.js swagger-ui.css LICENSE) do
      assert swagger =~ "node_modules/swagger-ui-dist/#{asset}"
    end

    refute Enum.any?(native, &Regex.match?(~r/^COPY (?:\.\.?\/?\.?|vendor)\s/, &1))

    refute Enum.any?(
             native,
             &Regex.match?(~r/^COPY .*\b(?:Gemfile|spec|app\/models|config\/initializers)\b/, &1)
           )

    refute Enum.any?(native, &(&1 =~ ~r/^RUN .*swagger\.yaml/))

    ignored = File.read!(Path.expand("../../../../.dockerignore", __DIR__))

    for path <- ~w(.env* .scratch/ storage/ config/master.key) do
      assert path in String.split(ignored, "\n")
    end
  end

  @tag :a12f4_b02_2
  test "explicit payload preserves assets renderer geo data and public volume synchronization" do
    native = native_stage()
    payload = Enum.join(native, "\n")

    for copy <- [
          "COPY --from=phoenix_builder /build/_build/prod/rel/dawarich /opt/dawarich",
          "COPY --from=phoenix_builder /out/public/assets public/assets",
          "COPY --from=phoenix_builder /out/config/sprockets-manifest.json config/sprockets-manifest.json",
          "COPY --from=phoenix_builder /out/tmp/phoenix tmp/phoenix",
          "COPY --from=phoenix_builder #{builder_css_path()} #{@css}",
          "COPY --from=poster_builder /renderer vendor/poster_renderer",
          "COPY app/javascript app/javascript",
          "COPY app/assets/fonts app/assets/fonts",
          "COPY vendor/javascript vendor/javascript",
          "COPY config/storage.yml config/storage.yml",
          "COPY .app_version .app_version"
        ] do
      assert copy in native
    end

    for dir <- ~w(maplibre maps maps_maplibre poster_themes) do
      assert "COPY public/#{dir} public/#{dir}" in native
    end

    for extension <- ~w(html png ico svg txt webmanifest) do
      assert payload =~ "public/*.#{extension}"
    end

    assert payload =~
             "mkdir -p storage log tmp/pids tmp/cache tmp/sockets public/imports public/exports"

    assert payload =~ "chmod -R 777 storage log tmp public"
    assert payload =~ "cp -r public $APP_PATH/public_dist"
    refute payload =~ "ENV LD_LIBRARY_PATH"

    {"phoenix_builder", builder} = List.keyfind(stages(), "phoenix_builder", 0)
    assert "COPY lib/assets lib/assets" in builder
    assert "COPY config/shared_link_wordlist.txt priv/shared_link_wordlist.txt" in builder
    assert "COPY lib/assets/admin1_world.geojson priv/admin1_world.geojson" in builder
    assert "COPY lib/assets/countries.geojson.gz priv/countries.geojson.gz" in builder

    {"poster_builder", renderer} = List.keyfind(stages(), "poster_builder", 0)
    renderer = Enum.join(renderer, "\n")

    assert renderer =~
             "vendor/poster_renderer/package.json vendor/poster_renderer/package-lock.json"

    assert renderer =~ "COPY vendor/poster_renderer/fonts fonts"
    assert renderer =~ "npm ci --no-audit --no-fund"
    assert renderer =~ ~s|test "$(node -p 'process.versions.modules')" = 115|
    assert renderer =~ ~s([ "$TARGETARCH" = "amd64" ] || [ "$TARGETARCH" = "arm64" ])
    assert payload =~ "require('@maplibre/maplibre-gl-native'); require('canvas')"
  end

  @tag :a12f4_b03_2
  test "image recipe explicitly rejects Ruby tools and application source payload" do
    native = native_stage()
    assertion = Enum.find(native, &String.starts_with?(&1, "RUN for tool in "))
    assert assertion, "the native build must reject Ruby executables and source payload"
    shell = String.replace_prefix(assertion, "RUN ", "")
    root = Path.join(System.tmp_dir!(), "native_payload_#{System.unique_integer([:positive])}")
    tools = Path.join(root, "tools")
    File.mkdir_p!(tools)
    on_exit(fn -> File.rm_rf!(root) end)
    env = [{"APP_PATH", root}, {"PATH", tools}]

    assert {"", 0} = System.cmd("/bin/sh", ["-c", shell], env: env)

    for tool <- ~w(ruby bundle gem rake rails puma sidekiq) do
      path = Path.join(tools, tool)
      File.write!(path, "#!/bin/sh\nexit 0\n")
      File.chmod!(path, 0o755)
      assert {"", 1} == System.cmd("/bin/sh", ["-c", shell], env: env)
      File.rm!(path)
    end

    for source <-
          ~w(Gemfile Gemfile.lock .ruby-version bin/rails bin/rake config/application.rb config/boot.rb config/environment.rb spec app/controllers app/models app/jobs app/helpers app/views app/mailers app/services app/policies db/schema.rb vendor/bundle lib/tasks) do
      path = Path.join(root, source)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "probe")
      assert {"", 1} == System.cmd("/bin/sh", ["-c", shell], env: env)
      File.rm!(path)
    end

    libraries = Enum.find(native, &String.starts_with?(&1, "RUN for path in /usr/local/lib/ruby"))
    assert libraries
    assert libraries =~ "/usr/lib/ruby"
    assert libraries =~ "/usr/local/bundle"
    assert libraries =~ "/var/lib/gems"
    assert libraries =~ ~s([ ! -e "$path" ] || exit 1)
    assert Enum.join(native, "\n") =~ "dawarich eval 'Dawarich.Release.check_runtime_apps!()'"
  end

  defp builder_css_path do
    {"phoenix_builder", lines} = List.keyfind(stages(), "phoenix_builder", 0)
    tailwind = Enum.find_index(lines, &String.contains?(&1, "node_modules/.bin/tailwindcss"))
    assert tailwind, "the builder stage no longer runs Tailwind"

    [_, out] = Regex.run(~r/ -o (\S+)/, Enum.at(lines, tailwind))
    assert out == @css

    workdir =
      lines
      |> Enum.take(tailwind)
      |> Enum.filter(&String.starts_with?(&1, "WORKDIR "))
      |> List.last()
      |> String.replace_prefix("WORKDIR ", "")

    Path.join(workdir, out)
  end

  test "the final image carries the Tailwind file the manifest was built from, over the checkout's copy" do
    {_, final} = List.last(stages())
    checkout = Enum.find_index(final, &Regex.match?(~r/^COPY \.\.\/\.\s/, &1))

    fresh =
      Enum.find_index(final, &(&1 == "COPY --from=phoenix_builder #{builder_css_path()} #{@css}"))

    assert checkout, "the final stage no longer copies the checkout"
    assert fresh, "the final stage does not copy the builder's #{@css}"
    assert fresh > checkout, "the checkout's stale #{@css} would overwrite the builder's"
  end
end
