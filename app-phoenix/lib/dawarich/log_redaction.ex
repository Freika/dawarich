defmodule Dawarich.LogRedaction do
  @moduledoc false

  @filtered "[FILTERED]"
  @depth 12

  def install do
    :persistent_term.put({__MODULE__, :words}, configured_words())
    filter = {&__MODULE__.filter/2, []}
    :logger.add_primary_filter(__MODULE__, filter)

    :logger.add_handler_filter(:default, __MODULE__, {&__MODULE__.handler_filter/2, []})
    :ok
  end

  def handler_filter(%{meta: %{dawarich_redacted: true}}, _), do: :ignore
  def handler_filter(event, config), do: filter(event, config)

  def filter(event, _) do
    event
    |> redact()
    |> Map.update(:meta, %{}, &scrub/1)
    |> put_in([:meta, :dawarich_redacted], true)
  rescue
    _ -> %{event | msg: {:string, @filtered}} |> Map.put(:meta, %{})
  end

  defp redact(%{msg: {:report, report}} = event), do: %{event | msg: {:report, scrub(report)}}

  defp redact(%{meta: %{mfa: {Ecto.Adapters.SQL, _, _}}, msg: {:string, chardata}} = event),
    do: %{event | msg: {:string, scrub_sql(chardata)}}

  defp redact(%{msg: {:string, chardata}} = event),
    do: %{event | msg: {:string, scrub_chardata(chardata)}}

  defp redact(%{msg: {format, args}} = event) when is_list(args),
    do: %{event | msg: {format, scrub(args)}}

  defp redact(event), do: event

  def scrub(term), do: scrub(term, @depth)

  defp scrub(_term, 0), do: @filtered

  defp scrub(%Plug.Conn{} = conn, _depth),
    do: %{method: conn.method, request_path: request_path(conn.request_path), status: conn.status}

  defp scrub(%FunctionClauseError{} = error, _depth), do: %{error | args: nil}

  defp scrub(%Postgrex.Error{} = error, _depth) do
    postgres =
      if error.postgres,
        do:
          error.postgres |> Map.take([:code, :pg_code, :severity]) |> Map.put(:message, @filtered)

    %{error | message: @filtered, postgres: postgres, query: if(error.query, do: @filtered)}
  end

  defp scrub(%{__struct__: _} = struct, depth) do
    struct
    |> Map.from_struct()
    |> Enum.reduce(struct, fn {key, value}, acc ->
      Map.put(acc, key, scrub_pair(key, value, depth))
    end)
  rescue
    _ -> @filtered
  end

  defp scrub(map, depth) when is_map(map) do
    map =
      if is_binary(map[:query]) and sensitive_sql?(map.query),
        do:
          Map.new(map, fn {key, value} ->
            {key, if(key in [:params, :cast_params, :result], do: @filtered, else: value)}
          end),
        else: map

    Map.new(map, fn {key, value} -> {key, scrub_pair(key, value, depth)} end)
  end

  defp scrub(list, depth) when is_list(list) do
    cond do
      List.improper?(list) ->
        @filtered

      Keyword.keyword?(list) and is_binary(Keyword.get(list, :query)) ->
        list |> Map.new() |> scrub(depth) |> Map.to_list()

      true ->
        Enum.map(list, &scrub(&1, depth - 1))
    end
  end

  defp scrub({key, value}, depth) when is_atom(key) or is_binary(key),
    do: {key, scrub_pair(key, value, depth)}

  defp scrub(tuple, depth) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.map(&scrub(&1, depth - 1)) |> List.to_tuple()

  defp scrub(binary, _depth) when is_binary(binary), do: scrub_binary(binary)
  defp scrub(term, _depth), do: term

  defp scrub_pair(key, value, depth),
    do: if(sensitive?(key), do: @filtered, else: scrub(value, depth - 1))

  defp scrub_sql([_, _, _, _, _, _, _, _, ?\n, query, ?\s, _params, _] = data) do
    if sensitive_sql?(query),
      do: data |> List.replace_at(11, @filtered) |> scrub_chardata(),
      else: scrub_chardata(data)
  end

  defp scrub_sql(chardata) do
    text = IO.chardata_to_string(chardata)

    if sensitive_sql?(text),
      do: hd(String.split(text, "\n", parts: 2)) <> "\n" <> @filtered,
      else: scrub_binary(text)
  end

  defp sensitive_sql?(sql) do
    words = words()
    words != [] and mentions?(IO.iodata_to_binary(sql), words)
  end

  defp scrub_chardata(chardata) do
    chardata |> IO.chardata_to_string() |> scrub_binary()
  rescue
    _ -> @filtered
  end

  def request_path(path) do
    path = scrub_storage_paths(path)

    Regex.replace(
      ~r{(/(?:family/)?invitations/|/s/|/api/v1/shared/|/shared/(?:month|digest|achievements)/)[^/\s?"'<>]++},
      path,
      "\\1" <> @filtered
    )
  end

  defp scrub_binary(binary) do
    binary = binary |> request_path() |> scrub_uuids()

    case words() do
      [] ->
        binary

      words ->
        cond do
          String.contains?(binary, "\n  Session: ") ->
            [diagnostic, _session] = String.split(binary, "\n  Session: ", parts: 2)
            scrub_binary(diagnostic) <> "\n  Session: " <> @filtered

          String.contains?(binary, "Postgrex.Error") ->
            scrub_postgres(binary)

          not mentions?(binary, words) ->
            binary

          Regex.match?(~r/(?<![[:alnum:]_])"?(?:cast_)?params"?\s*+(?::|=>|=)/, binary) ->
            @filtered

          true ->
            binary |> scrub_pairs() |> scrub_json() |> scrub_session() |> scrub_inspect()
        end
    end
  rescue
    _ -> @filtered
  end

  defp scrub_postgres(binary) do
    [prefix, _] = String.split(binary, "Postgrex.Error", parts: 2)

    [_, message] = String.split(binary, "Postgrex.Error", parts: 2)

    case Regex.run(~r/\A: Database error(?: \(SQLSTATE ([0-9A-Z]{5})\))?\z/, message) do
      [_, code] ->
        scrub_binary(prefix) <> "Postgrex.Error: Database error (SQLSTATE #{code})"

      [_] ->
        scrub_binary(prefix) <> "Postgrex.Error: Database error"

      _ ->
        code =
          case Regex.run(~r/Postgrex\.Error\)?\s+(ERROR|FATAL|PANIC) ([0-9A-Z]{5})/, binary) do
            [_, severity, code] -> severity <> " " <> code <> " "
            _ -> ""
          end

        scrub_binary(prefix) <> "Postgrex.Error " <> code <> @filtered
    end
  end

  defp scrub_uuids(binary) do
    Regex.replace(
      ~r/(?<![[:xdigit:]])[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}(?![[:xdigit:]])/,
      binary,
      @filtered
    )
  end

  defp scrub_storage_paths(binary) do
    Regex.replace(
      ~r{(/rails/active_storage/(?:disk|blobs(?:/(?:redirect|proxy))?|representations(?:/(?:redirect|proxy))?)/)[^\s"'?#]++},
      binary,
      "\\1" <> @filtered
    )
  end

  defp mentions?(binary, words), do: :binary.match(String.downcase(binary), words) != :nomatch

  defp scrub_pairs(binary, depth \\ 2) do
    Regex.replace(
      ~r/(?<![^\s&?;,"'])([^\s&=?;,"']++)=("(?:[^"\\]|\\.)*+"|'(?:[^'\\]|\\.)*+'|[^&\s]*+)/,
      binary,
      fn whole, key, value ->
        cond do
          sensitive?(key) -> key <> "=" <> @filtered
          depth > 0 and String.contains?(value, "?") -> key <> "=" <> scrub_query(value, depth)
          true -> whole
        end
      end
    )
  end

  defp scrub_query(value, depth) do
    [path, query] = String.split(value, "?", parts: 2)
    path <> "?" <> scrub_pairs(query, depth - 1)
  end

  defp scrub_json(binary) do
    Regex.replace(~r/"([^"\\]*+)"(\s*+:\s*+)"(?:[^"\\]|\\.)*+"/, binary, fn whole, key, colon ->
      if sensitive?(key), do: ~s("#{key}"#{colon}"#{@filtered}"), else: whole
    end)
  end

  defp scrub_session(binary) do
    Regex.replace(
      ~r/"([^"\\]*+)"(\s*+=>\s*+)"(?:[^"\\]|\\.)*+"/,
      binary,
      fn whole, key, arrow ->
        if sensitive?(key), do: ~s("#{key}"#{arrow}"#{@filtered}"), else: whole
      end
    )
  end

  defp scrub_inspect(binary) do
    Regex.replace(
      ~r/(?<![\w"])([a-z_][a-z0-9_]*+)(\s*+:\s*+)"(?:[^"\\]|\\.)*+"/,
      binary,
      fn whole, key, colon ->
        if sensitive?(key), do: key <> colon <> ~s("#{@filtered}"), else: whole
      end
    )
  end

  defp sensitive?(key) when is_atom(key), do: sensitive?(Atom.to_string(key))

  defp sensitive?(key) when is_binary(key) do
    key = String.downcase(key)
    Enum.any?(words(), &String.contains?(key, &1))
  end

  defp sensitive?(_key), do: false

  defp words, do: :persistent_term.get({__MODULE__, :words}, nil) || configured_words()

  defp configured_words,
    do: Application.get_env(:dawarich, __MODULE__, []) |> Keyword.get(:words, []) |> List.wrap()
end
