defmodule Dawarich.Test.AfterCommitGuard do
  def violations(paths) do
    modules = Enum.flat_map(paths, &functions/1)

    graph =
      Enum.reduce(modules, %{}, fn {key, body, aliases, module, _file, _params}, graph ->
        Map.update(graph, key, calls(body, aliases, module), fn previous ->
          Enum.uniq(previous ++ calls(body, aliases, module))
        end)
      end)

    definitions = Enum.group_by(modules, &elem(&1, 0))

    sinks =
      for {key, body, aliases, _, _, _} <- modules,
          sink?(body, aliases),
          into: MapSet.new(),
          do: key

    reachable = reachable_sinks(graph, sinks)

    for {key, body, aliases, module, file, _params} <- modules,
        closure <- Dawarich.Test.TransactionRoots.find(body, aliases, module, definitions),
        target <- if(sink?(closure, aliases), do: [key], else: calls(closure, aliases, module)),
        MapSet.member?(reachable, target),
        do: {file, key, target}
  end

  defp functions(path) do
    ast = path |> File.read!() |> Code.string_to_quoted!() |> normalize()

    {_ast, modules} =
      Macro.prewalk(ast, [], fn
        {:defmodule, _, [name, [do: body]]} = node, acc ->
          module = module_name(name, %{})
          aliases = aliases(body, module)

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
                         path, Enum.take(args, arity)}

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

  defp aliases(body, module) do
    {_ast, result} =
      Macro.prewalk(body, %{__MODULE__: module}, fn
        {:alias, _, [{{:., _, [base, :{}]}, _, names}]} = node, acc ->
          parent = module_name(base, acc)

          result =
            Enum.reduce(names, acc, fn {:__aliases__, _, parts}, result ->
              Map.put(result, List.last(parts), parent <> "." <> Enum.join(parts, "."))
            end)

          {node, result}

        {:alias, _, [target]} = node, acc ->
          case module_name(target, acc) do
            nil ->
              {node, acc}

            name ->
              {node,
               Map.put(acc, name |> String.split(".") |> List.last() |> String.to_atom(), name)}
          end

        {:alias, _, [target, [as: {:__aliases__, _, [short]}]]} = node, acc ->
          {node, Map.put(acc, short, module_name(target, acc))}

        node, acc ->
          {node, acc}
      end)

    result
  end

  def module_name({:__aliases__, _, [:"Elixir" | rest]}, _),
    do: Enum.join(["Elixir" | rest], ".")

  def module_name({:__aliases__, _, [short | rest]}, aliases) do
    base =
      if is_atom(short),
        do: Map.get(aliases, short, "Elixir." <> to_string(short)),
        else: module_name(short, aliases)

    if is_binary(base) and Enum.all?(rest, &is_atom/1), do: Enum.join([base | rest], ".")
  end

  def module_name({:__MODULE__, _, _}, aliases), do: Map.get(aliases, :__MODULE__)

  def module_name(module, _) when is_atom(module) and not is_nil(module),
    do: Atom.to_string(module)

  def module_name(module, _) when is_binary(module), do: module
  def module_name(_, _), do: nil

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

  defp normalize(ast) do
    Macro.prewalk(ast, fn
      {:|>, _, [left, right]} ->
        Macro.pipe(left, right, 0)

      {:&, meta, [{:/, _, [target, arity]}]} when is_integer(arity) ->
        {name, call_meta, _args} = target
        {:&, meta, [{name, call_meta, List.duplicate(nil, arity)}]}

      node ->
        node
    end)
  end

  defp sink?(ast, aliases) do
    {_ast, found} =
      Macro.prewalk(ast, false, fn
        {{:., _, [target, name]}, _, args} = node, acc when is_list(args) ->
          module = module_name(target, aliases)

          invalidates =
            (module == "Elixir.Dawarich.TtlCache" and name in [:delete, :delete_digest]) or
              (module == "Elixir.Dawarich.Redis" and name == :cache_command and eviction?(args))

          {node, acc or invalidates}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp eviction?(args) do
    {_ast, found} =
      Macro.prewalk(args, false, fn
        value, acc when is_binary(value) ->
          {value, acc or value in ["DEL", "UNLINK"] or String.contains?(value, "tile_epoch")}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp reachable_sinks(graph, sinks) do
    barrier = {"Elixir.Dawarich.RailsCache", :entry, 3}

    reverse =
      for {source, targets} <- graph,
          source != barrier,
          target <- targets,
          target != barrier,
          reduce: %{} do
        acc -> Map.update(acc, target, [source], &[source | &1])
      end

    mark_reachable(sinks |> MapSet.delete(barrier) |> MapSet.to_list(), reverse, MapSet.new())
  end

  defp mark_reachable([], _reverse, reachable), do: reachable

  defp mark_reachable([target | rest], reverse, reachable) do
    if MapSet.member?(reachable, target),
      do: mark_reachable(rest, reverse, reachable),
      else:
        mark_reachable(
          Map.get(reverse, target, []) ++ rest,
          reverse,
          MapSet.put(reachable, target)
        )
  end
end
