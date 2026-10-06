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
