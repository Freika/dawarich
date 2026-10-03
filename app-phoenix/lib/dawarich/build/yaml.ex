defmodule Dawarich.Build.Yaml do
  @moduledoc false

  alias Jason.OrderedObject

  def load!(path) do
    {:ok, _} = Application.ensure_all_started(:yamerl)

    documents =
      try do
        :yamerl_constr.file(String.to_charlist(path), [
          :str_node_as_binary,
          {:schema, :core},
          {:detailed_constr, true},
          {:keep_duplicate_keys, true}
        ])
      catch
        kind, reason -> raise ArgumentError, "#{path}: #{Exception.format_banner(kind, reason)}"
      end

    case documents do
      [{:yamerl_doc, root}] -> node!(root, path)
      _ -> raise ArgumentError, "#{path}: expected one YAML document, got #{length(documents)}"
    end
  end

  defp node!({:yamerl_map, _, _, _, pairs}, path) do
    values =
      Enum.reduce(pairs, [], fn {key, value}, acc ->
        name = key!(key, path)

        if name == "<<" or List.keymember?(acc, name, 0),
          do: raise(ArgumentError, "#{path}: duplicate or merge key #{inspect(name)}")

        [{name, node!(value, path)} | acc]
      end)

    %OrderedObject{values: Enum.reverse(values)}
  end

  defp node!({:yamerl_seq, _, _, _, entries, _}, path), do: Enum.map(entries, &node!(&1, path))
  defp node!({:yamerl_str, _, _, _, text}, _path), do: text
  defp node!({:yamerl_null, _, _, _}, _path), do: nil
  defp node!({:yamerl_bool, _, _, _, value}, _path), do: value
  defp node!({:yamerl_int, _, _, _, value}, _path), do: value
  defp node!({:yamerl_float, _, _, _, value}, _path), do: value

  defp node!(node, path),
    do: raise(ArgumentError, "#{path}: unsupported YAML node #{inspect(elem(node, 0))}")

  defp key!({:yamerl_str, _, _, _, text}, _path), do: text
  defp key!(node, path), do: raise(ArgumentError, "#{path}: non-string key #{inspect(node)}")
end
