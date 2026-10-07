defmodule Dawarich.Test.TransactionRoots do
  alias Dawarich.Test.AfterCommitGuard, as: Guard

  def find(ast, aliases, module, definitions, bindings \\ %{}, seen \\ MapSet.new()) do
    {_ast, roots} =
      Macro.prewalk(ast, {bindings, []}, fn
        {:=, _, [{name, _, context}, value]} = node, {bindings, roots}
        when is_atom(name) and is_atom(context) ->
          {node, {Map.put(bindings, name, resolve(value, bindings)), roots}}

        node, {bindings, roots} ->
          found = roots(node, aliases, module, definitions, bindings, seen)
          {node, {bindings, roots ++ found}}
      end)

    roots |> elem(1) |> Enum.uniq()
  end

  defp roots(node, aliases, module, definitions, bindings, seen) do
    case call(node, aliases, module) do
      {_, :transaction, [callback | _]} ->
        callback_roots(resolve(callback, bindings))

      {"Elixir.Dawarich.Transaction", :run, [_repo, callback | _]} ->
        callback_roots(resolve(callback, bindings))

      {"Elixir.Ecto.Multi", :run, [_multi, _name, callback]} ->
        [resolve(callback, bindings)]

      {"Elixir.Ecto.Multi", :run, [_multi, _name, target, name, args]}
      when is_atom(name) and is_list(args) ->
        [{{:., [], [Guard.module_name(target, aliases), name]}, [], [nil, nil | args]}]

      {target, name, args} when is_list(args) ->
        key = {target, name, length(args)}
        args = Enum.map(args, &resolve(&1, bindings))

        if not MapSet.member?(seen, key) and Enum.any?(args, &callback?/1) do
          for {_, body, target_aliases, target_module, _, params} <-
                Map.get(definitions, key, []),
              root <-
                find(
                  body,
                  target_aliases,
                  target_module,
                  definitions,
                  bind(params, args, aliases, module, definitions),
                  MapSet.put(seen, key)
                ),
              do: root
        else
          []
        end

      _ ->
        []
    end
  end

  defp callback_roots({kind, _, _} = callback) when kind in [:fn, :&], do: [callback]
  defp callback_roots(_), do: []

  defp call({{:., _, [target, name]}, _, args}, aliases, _) when is_list(args),
    do: {Guard.module_name(target, aliases), name, args}

  defp call({name, _, args}, _, module) when is_atom(name) and is_list(args),
    do: {module, name, args}

  defp call(_, _, _), do: nil

  defp resolve({name, _, context} = node, bindings) when is_atom(name) and is_atom(context),
    do: Map.get(bindings, name, node)

  defp resolve(ast, _), do: ast

  defp callback?(ast) do
    {_ast, found} =
      Macro.prewalk(ast, false, fn
        {name, _, _} = node, _found when name in [:fn, :&] -> {node, true}
        node, found -> {node, found}
      end)

    found
  end

  defp bind(params, args, aliases, module, definitions) do
    for {{name, _, context}, arg} <- Enum.zip(params, args),
        is_atom(name) and is_atom(context),
        into: %{},
        do: {name, qualify(arg, aliases, module, definitions)}
  end

  defp qualify(ast, aliases, module, definitions) do
    Macro.prewalk(ast, fn node ->
      case call(node, aliases, module) do
        {target, name, args} when is_binary(target) ->
          if Map.has_key?(definitions, {target, name, length(args)}) or target != module,
            do: {{:., [], [target, name]}, [], args},
            else: node

        _ ->
          node
      end
    end)
  end
end
