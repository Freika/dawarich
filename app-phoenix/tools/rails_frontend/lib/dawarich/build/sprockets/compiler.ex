defmodule Dawarich.Build.Sprockets.Compiler do
  @moduledoc false

  alias Dawarich.Build.Sprockets.{Directives, Env, Processors, Writer}

  @precompile ~w(manifest.js turbo.js turbo.min.js turbo.min.js.map stimulus.js stimulus.min.js
                 stimulus.min.js.map actioncable.js actioncable.esm.js activestorage activestorage.esm
                 actiontext.js actiontext.esm.js trix.js trix.css chartkick.js Chart.bundle.js inter-font.css)

  def compile(root, precompile \\ @precompile) do
    env = Env.new(root)

    {lists, _cache} =
      Enum.map_reduce(precompile, %{}, fn path, cache ->
        asset =
          Env.resolve(env, path, nil, root) ||
            raise(ArgumentError, "precompile: #{path} not found")

        linked(env, asset, cache)
      end)

    lists |> List.flatten() |> Enum.uniq_by(& &1.logical)
  end

  def build(env, asset, cache) do
    case Map.fetch(cache, asset) do
      {:ok, result} ->
        {result, cache}

      :error ->
        {source, links, cache} = source(env, asset, cache)

        result = %{
          logical: asset.logical,
          source: source,
          links: Enum.uniq(links),
          gzip: asset.erb or asset.kind in [:js, :css, :map, :svg, :ico],
          digest_path: Writer.digest_path(asset.logical, source)
        }

        {result, Map.put(cache, asset, result)}
    end
  end

  def dfs(initial, children), do: walk(initial, MapSet.new(), [], children)

  defp walk([], _seen, nodes, _children), do: nodes |> Enum.reverse() |> Enum.uniq()

  defp walk([node | stack], seen, nodes, children) do
    if MapSet.member?(seen, node),
      do: walk(stack, seen, [node | nodes], children),
      else: walk(children.(node) ++ [node | stack], MapSet.put(seen, node), nodes, children)
  end

  defp linked(env, asset, cache) do
    {root, cache} = build(env, asset, cache)
    bfs(env, root.links, MapSet.new(root.links), [root], cache)
  end

  defp bfs(_env, [], _seen, acc, cache), do: {Enum.reverse(acc), cache}

  defp bfs(env, [asset | queue], seen, acc, cache) do
    {result, cache} = build(env, asset, cache)
    fresh = Enum.reject(result.links, &MapSet.member?(seen, &1))
    bfs(env, queue ++ fresh, Enum.into(fresh, seen), [result | acc], cache)
  end

  defp source(env, %{kind: :xml, erb: true} = asset, cache),
    do: render(env, asset, File.read!(asset.file), cache)

  defp source(_env, %{kind: :map} = asset, cache),
    do: {Processors.read_text(asset.file, :map), [], cache}

  defp source(env, %{kind: kind} = asset, cache) when kind in [:js, :css] do
    graph = &directives(env, &1).required
    parts = dfs([asset], graph) -- dfs(directives(env, asset).stubbed, graph)
    {outputs, cache} = Enum.map_reduce(parts, cache, &self_process(env, &1, &2))
    data = Enum.map(outputs, &elem(&1, 0))
    source = if kind == :js, do: Processors.concat_js(data), else: IO.iodata_to_binary(data)
    {source, Enum.flat_map(outputs, &elem(&1, 1)), cache}
  end

  defp source(_env, asset, cache), do: {File.read!(asset.file), [], cache}

  defp self_process(env, part, cache) do
    case Map.fetch(cache, {:self, part}) do
      {:ok, output} ->
        {output, cache}

      :error ->
        {data, links, cache} = self_source(env, part, cache)
        {{data, links}, Map.put(cache, {:self, part}, {data, links})}
    end
  end

  defp self_source(env, %{kind: :css, erb: true} = part, cache) do
    {text, erb_links, cache} = render(env, part, Processors.read_text(part.file, :css), cache)
    {data, url_links, cache} = urls(env, part, text, cache)
    {data, erb_links ++ url_links, cache}
  end

  defp self_source(env, %{kind: :css} = part, cache) do
    {text, _} = Directives.split(Processors.read_text(part.file, :css))
    {data, url_links, cache} = urls(env, part, text, cache)
    {data, directives(env, part).links ++ url_links, cache}
  end

  defp self_source(env, %{kind: :js} = part, cache) do
    {text, _} = Directives.split(Processors.read_text(part.file, :js))
    {data, map_links, cache} = sourcemaps(env, part, text, cache)
    {data, directives(env, part).links ++ map_links, cache}
  end

  defp directives(_env, %{erb: true}), do: %{required: [], stubbed: [], links: []}

  defp directives(env, part) do
    {_data, directives} = Directives.split(Processors.read_text(part.file, part.kind))

    Enum.reduce(
      directives,
      %{required: [], stubbed: [], links: []},
      &directive(env, part, &1, &2)
    )
  end

  defp directive(env, part, {"require", [path]}, acc),
    do: add(acc, :required, [resolve!(env, path, part, part.kind)])

  defp directive(_env, part, {"require_self", []}, acc), do: add(acc, :required, [part])

  defp directive(env, part, {"require_tree", args}, acc),
    do: add(acc, :required, tree(env, part, args, part.kind, true))

  defp directive(env, part, {"stub", [path]}, acc),
    do: add(acc, :stubbed, [resolve!(env, path, part, part.kind)])

  defp directive(env, part, {"link", [path]}, acc),
    do: add(acc, :links, [resolve!(env, path, part, nil)])

  defp directive(env, part, {"link_tree", [path | ext]}, acc),
    do: add(acc, :links, tree(env, part, [path], accept(ext), true))

  defp directive(env, part, {"link_directory", [path | ext]}, acc),
    do: add(acc, :links, tree(env, part, [path], accept(ext), false))

  defp directive(_env, part, {name, args}, _acc),
    do:
      raise(
        ArgumentError,
        "#{part.file}: unsupported Sprockets directive #{Enum.join([name | args], " ")}"
      )

  defp add(acc, key, assets), do: Map.update!(acc, key, &(&1 ++ assets))

  defp accept([]), do: nil
  defp accept([ext]), do: Env.accept(ext)

  defp tree(env, part, args, accept, recursive) do
    dir = Path.expand(List.first(args, "."), Path.dirname(part.file))

    for file <- Env.tree(dir, recursive),
        file != part.file,
        File.regular?(file),
        asset <- List.wrap(Env.asset(env, file, accept)),
        do: asset
  end

  defp resolve!(env, path, part, accept),
    do:
      Env.resolve(env, path, accept, Path.dirname(part.file)) ||
        raise(ArgumentError, "#{part.file}: cannot resolve #{path}")

  defp urls(env, part, text, cache) do
    {map, links, cache} = resolve_all(env, part, Processors.url_paths(text), cache)
    {Processors.rewrite_urls(text, map), links, cache}
  end

  defp render(env, part, text, cache) do
    {map, links, cache} = resolve_all(env, part, Processors.erb_paths(text, part.file), cache)
    {Processors.render_erb(text, map), links, cache}
  end

  defp resolve_all(env, part, paths, cache) do
    Enum.reduce(paths, {%{}, [], cache}, fn path, {map, links, cache} ->
      {url, link, cache} = asset_path(env, part, path, cache)
      {Map.put(map, path, url), links ++ List.wrap(link), cache}
    end)
  end

  defp asset_path(env, part, path, cache) do
    {source, tail} = Processors.split_tail(path)

    cond do
      Processors.uri?(path) ->
        {path, nil, cache}

      String.starts_with?(source, "/") ->
        {source <> tail, nil, cache}

      target = Env.resolve(env, source, nil, Path.dirname(part.file)) ->
        {result, cache} = build(env, target, cache)
        {"/assets/" <> result.digest_path <> tail, target, cache}

      true ->
        {"/" <> source <> tail, nil, cache}
    end
  end

  defp sourcemaps(env, part, text, cache) do
    {map, links, cache} =
      Enum.reduce(Processors.sourcemap_refs(text), {%{}, [], cache}, fn ref,
                                                                        {map, links, cache} ->
        case Env.resolve(env, Processors.sibling(part.logical, ref), nil, Path.dirname(part.file)) do
          %{kind: :map} = target ->
            {result, cache} = build(env, target, cache)
            comment = "//# sourceMappingURL=/assets/#{result.digest_path}\n//!\n"
            {Map.put(map, ref, comment), links ++ [target], cache}

          _ ->
            {Map.put(map, ref, ""), links, cache}
        end
      end)

    {Processors.rewrite_sourcemaps(text, map), links, cache}
  end
end
