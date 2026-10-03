defmodule Dawarich.Build.DockerfileTest do
  use ExUnit.Case, async: true

  alias Dawarich.RailsTree

  @css "app/assets/builds/tailwind.css"

  defp stages do
    RailsTree.read("docker/Dockerfile")
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
