defmodule Dawarich.Build.Importmap do
  @moduledoc false

  alias Jason.OrderedObject

  @call ~r/\A(pin|pin_all_from)\s+(["'])([^"'\\#]+)\2((?:\s*,\s*\w+:\s*(?:"[^"\\#]*"|'[^'\\]*'|true|false))*)\s*(?:#.*)?\z/
  @option ~r/(\w+):\s*(?:"([^"]*)"|'([^']*)'|(true|false))/
  @options %{"pin" => ~w(to preload), "pin_all_from" => ~w(under to preload)}
  @uri ~r{\A(?:[-a-z]+://|cid:|data:|//)}i

  def export(root, assets) do
    imports = for {name, path} <- expand(entries(root), root), do: {name, resolve(path, assets)}

    Jason.encode_to_iodata!(
      %OrderedObject{values: [{"imports", %OrderedObject{values: imports}}]},
      pretty: true
    )
  end

  defp entries(root) do
    root
    |> Path.join("config/importmap.rb")
    |> File.read!()
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
    |> Enum.map(&entry!/1)
  end

  defp entry!(line) do
    case Regex.run(@call, line) do
      [_, call, _quote, argument, options | _] -> {call, argument, options!(call, options, line)}
      _ -> raise ArgumentError, "config/importmap.rb: unsupported line: #{line}"
    end
  end

  defp options!(call, text, line) do
    Map.new(Regex.scan(@option, text), fn [_, key | values] ->
      unless key in @options[call],
        do: raise(ArgumentError, "config/importmap.rb: unsupported option #{key}: #{line}")

      {key, Enum.find(values, &(&1 != ""))}
    end)
  end

  defp expand(entries, root) do
    packages =
      for {"pin", name, options} <- entries, reduce: [] do
        acc -> List.keystore(acc, name, 0, {name, options["to"] || name <> ".js"})
      end

    for {"pin_all_from", dir, options} <- entries, reduce: packages do
      acc -> Enum.reduce(modules(root, dir, options), acc, &List.keystore(&2, elem(&1, 0), 0, &1))
    end
  end

  defp modules(root, dir, options) do
    base = Path.expand(dir, root)
    prefix = options["to"] || options["under"]

    for file <- base |> Path.join("**/*.{js,jsm}") |> Path.wildcard() |> Enum.sort(),
        File.regular?(file) do
      relative = Path.relative_to(file, base)
      {module_name(relative, options["under"]), join([prefix, relative])}
    end
  end

  defp module_name(relative, under) do
    stem =
      relative
      |> String.replace_suffix(Path.extname(relative), "")
      |> String.replace(~r{(?:/|\A)index\z}, "")

    join([under, stem])
  end

  defp join(parts), do: parts |> Enum.reject(&(&1 in [nil, ""])) |> Enum.join("/")

  defp resolve(path, assets) do
    cond do
      String.starts_with?(path, "/") or Regex.match?(@uri, path) -> path
      digest = assets[path] -> "/assets/" <> digest
      true -> raise ArgumentError, "importmap: #{path} is not in the asset manifest"
    end
  end
end
