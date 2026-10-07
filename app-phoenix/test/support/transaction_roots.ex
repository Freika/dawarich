defmodule Dawarich.Test.TransactionRoots do
  alias Dawarich.Test.AfterCommitGuard, as: Guard

  def find(ast, aliases, module, definitions, bindings \\ %{}, seen \\ MapSet.new()) do
    {_ast, roots} =
      Macro.prewalk(ast, {bindings, []}, fn
        {:=, _, [{name, _, context}, value]} = node, {bindings, roots}
        when is_atom(name) and is_atom(context) ->
          value = resolve(value, bindings)
          bindings = Map.delete(bindings, name)
          bindings = if callback?(value), do: Map.put(bindings, name, value), else: bindings
          {node, {bindings, roots}}

        node, {bindings, roots} ->
          found = roots(node, aliases, module, definitions, bindings, seen)
          {node, {bindings, roots ++ found}}
      end)

    roots |> elem(1) |> Enum.uniq()
  end

  defp roots(node, aliases, module, definitions, bindings, seen) do
    case call(node, aliases, module) do
      {target, :transaction, [callback | _] = args} ->
        if Map.has_key?(definitions, {target, :transaction, length(args)}) do
          forwarded_roots(
            target,
            :transaction,
            args,
            aliases,
            module,
            definitions,
            bindings,
            seen
          )
        else
          callback_roots(callback |> resolve(bindings) |> qualify(aliases, module, definitions))
        end

      {"Elixir.Dawarich.Transaction", :run, [_repo, callback | _]} ->
        callback_roots(callback |> resolve(bindings) |> qualify(aliases, module, definitions))

      {"Elixir.Ecto.Multi", :run, [_multi, _name, callback]} ->
        [callback |> resolve(bindings) |> qualify(aliases, module, definitions)]

      {"Elixir.Ecto.Multi", :run, [_multi, _name, target, name, args]}
      when is_atom(name) and is_list(args) ->
        [{{:., [], [Guard.module_name(target, aliases), name]}, [], [nil, nil | args]}]

      {:anonymous, callback, args} ->
        invoked_roots(
          resolve(callback, bindings),
          Enum.map(args, &resolve(&1, bindings)),
          aliases,
          module,
          definitions,
          bindings,
          seen
        )

      {target, name, args} when is_list(args) ->
        forwarded_roots(target, name, args, aliases, module, definitions, bindings, seen)

      _ ->
        []
    end
  end

  defp forwarded_roots(target, name, args, aliases, module, definitions, bindings, seen) do
    key = {target, name, length(args)}
    args = Enum.map(args, &resolve(&1, bindings))

    if not MapSet.member?(seen, key) and Enum.any?(args, &callback?/1) do
      for {_, body, target_aliases, target_module, _, params} <- Map.get(definitions, key, []),
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
  end

  defp callback_roots({kind, _, _} = callback) when kind in [:fn, :&], do: [callback]
  defp callback_roots(_), do: []

  defp invoked_roots({:fn, _, clauses}, args, aliases, module, definitions, _bindings, seen) do
    for {:->, _, [params, body]} <- clauses,
        root <-
          find(
            body,
            aliases,
            module,
            definitions,
            bind(params, args, aliases, module, definitions),
            seen
          ),
        do: root
  end

  defp invoked_roots(
         {:&, _, [{target, meta, params}]},
         args,
         aliases,
         module,
         definitions,
         bindings,
         seen
       )
       when is_list(params) do
    params = if Enum.all?(params, &is_nil/1), do: args, else: params
    find({target, meta, params}, aliases, module, definitions, bindings, seen)
  end

  defp invoked_roots(_, _, _, _, _, _, _), do: []

  defp call({{:., _, [callback]}, _, args}, _, _) when is_list(args),
    do: {:anonymous, callback, args}

  defp call({{:., _, [target, name]}, _, args}, aliases, _) when is_list(args),
    do: {Guard.module_name(target, aliases), name, args}

  defp call({name, _, args}, _, module) when is_atom(name) and is_list(args),
    do: {module, name, args}

  defp call(_, _, _), do: nil

  defp resolve(ast, bindings) do
    Macro.postwalk(ast, fn
      {name, _, context} = node when is_atom(name) and is_atom(context) ->
        Map.get(bindings, name, node)

      node ->
        node
    end)
  end

  defp callback?({kind, _, _}) when kind in [:fn, :&], do: true
  defp callback?(_), do: false

  defp bind(params, args, aliases, module, definitions) do
    for {{name, _, context}, arg} <- Enum.zip(params, args),
        is_atom(name) and is_atom(context),
        callback?(arg),
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
          case node do
            {:__aliases__, _, _} -> Guard.module_name(node, aliases) || node
            {:__MODULE__, _, _} -> module
            _ -> node
          end
      end
    end)
  end
end
