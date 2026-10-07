defmodule Dawarich.AfterCommitGuardTest do
  use ExUnit.Case, async: true

  test "transaction closures cannot reach inline cache eviction or epoch bumps" do
    assert violations(Path.wildcard("lib/**/*.ex")) == []
  end

  defp violations(paths) do
    modules = Enum.flat_map(paths, &functions/1)

    graph =
      Enum.reduce(modules, %{}, fn {key, body, aliases, module, _file}, graph ->
        Map.update(graph, key, calls(body, aliases, module), fn previous ->
          Enum.uniq(previous ++ calls(body, aliases, module))
        end)
      end)

    sinks = for {key, body, _, _, _} <- modules, sink?(body), into: MapSet.new(), do: key

    for {key, body, aliases, module, file} <- modules,
        closure <- transactions(body),
        target <- if(sink?(closure), do: [key], else: calls(closure, aliases, module)),
        reaches?(target, graph, sinks, MapSet.new()),
        do: {file, key, target}
  end

  defp functions(path) do
    ast = path |> File.read!() |> Code.string_to_quoted!()

    {_ast, modules} =
      Macro.prewalk(ast, [], fn
        {:defmodule, _, [name, [do: body]]} = node, acc ->
          module = module_name(name, %{})
          aliases = aliases(body)

          defs =
            for {kind, _, [head, blocks]} <- expressions(body),
                kind in [:def, :defp],
                is_list(blocks),
                Keyword.has_key?(blocks, :do),
                reduce: [] do
              acc ->
                head =
                  case head do
                    {:when, _, [head | _]} -> head
                    head -> head
                  end

                {name, _, args} = head
                args = args || []
                defaults = Enum.count(args, &match?({:\\, _, _}, &1))

                rows =
                  for arity <- (length(args) - defaults)..length(args),
                      do:
                        {{module, name, arity}, Keyword.fetch!(blocks, :do), aliases, module,
                         path}

                acc ++ rows
            end

          {node, acc ++ defs}

        node, acc ->
          {node, acc}
      end)

    modules
  end

  defp expressions({:__block__, _, list}), do: list
  defp expressions(node), do: [node]

  defp aliases(body) do
    {_ast, result} =
      Macro.prewalk(body, %{}, fn
        {:alias, _, [{{:., _, [base, :{}]}, _, names}]} = node, acc ->
          parent = module_name(base, %{})

          result =
            Enum.reduce(names, acc, fn {:__aliases__, _, parts}, result ->
              Map.put(result, List.last(parts), parent <> "." <> Enum.join(parts, "."))
            end)

          {node, result}

        {:alias, _, [{:__aliases__, _, names}]} = node, acc ->
          {node, Map.put(acc, List.last(names), "Elixir." <> Enum.join(names, "."))}

        {:alias, _, [{:__aliases__, _, names}, [as: {:__aliases__, _, [short]}]]} = node, acc ->
          {node, Map.put(acc, short, "Elixir." <> Enum.join(names, "."))}

        node, acc ->
          {node, acc}
      end)

    result
  end

  defp module_name({:__aliases__, _, [short | rest]}, aliases) when is_atom(short) do
    if Enum.all?(rest, &is_atom/1) do
      Enum.join([Map.get(aliases, short, "Elixir." <> to_string(short)) | rest], ".")
    end
  end

  defp module_name(_, _), do: nil

  defp calls(ast, aliases, module) do
    {_ast, calls} =
      Macro.prewalk(ast, [], fn
        {{:., _, [target, name]}, _, args} = node, acc when is_list(args) ->
          {node, [{module_name(target, aliases), name, length(args)} | acc]}

        {name, _, args} = node, acc when is_atom(name) and is_list(args) ->
          {node, [{module, name, length(args)} | acc]}

        node, acc ->
          {node, acc}
      end)

    calls
  end

  defp sink?(ast) do
    {_ast, found} =
      Macro.prewalk(ast, false, fn
        {{:., _, [{:__aliases__, _, names}, :delete]}, _, _} = node, acc ->
          {node, acc or List.last(names) == :TtlCache}

        {{:., _, [_, :cache_command]}, _, [args | _]} = node, acc ->
          source = Macro.to_string(args)
          {node, acc or String.contains?(source, ["\"DEL\"", "\"UNLINK\"", "tile_epoch"])}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp transactions(ast) do
    {_ast, closures} =
      Macro.prewalk(ast, [], fn
        {{:., _, [_, :transaction]}, _, args} = node, acc ->
          {node, acc ++ Enum.filter(args, &match?({:fn, _, _}, &1))}

        {{:., _, [{:__aliases__, _, names}, :run]}, _, args} = node, acc ->
          if List.last(names) == :Transaction,
            do: {node, acc ++ Enum.filter(args, &match?({:fn, _, _}, &1))},
            else: {node, acc}

        node, acc ->
          {node, acc}
      end)

    closures
  end

  defp reaches?(target, graph, sinks, seen) do
    cond do
      target == {"Elixir.Dawarich.RailsCache", :entry, 3} ->
        false

      MapSet.member?(sinks, target) ->
        true

      MapSet.member?(seen, target) ->
        false

      true ->
        Enum.any?(
          Map.get(graph, target, []),
          &reaches?(&1, graph, sinks, MapSet.put(seen, target))
        )
    end
  end
end
