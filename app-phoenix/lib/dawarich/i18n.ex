defmodule Dawarich.I18n do
  @moduledoc false

  @default "en"
  @pattern ~r/%%|%\{(\w+)\}/
  @reserved_keys ~w(
    cascade deep_interpolation default exception_handler fallback
    fallback_in_progress fallback_original_locale format object raise
    resolve scope separator skip_interpolation throw
  )
  @reserved_pattern ~r/(?<!%)%\{(#{Enum.join(@reserved_keys, "|")})\}/

  def reserved_keys, do: @reserved_keys

  def t(locale, key, bindings \\ %{}, opts \\ []),
    do: lookup(translations(), locale, key, bindings, opts)

  def en!(key) do
    {:ok, value} = t("en", key)
    value
  end

  def available_locales, do: Map.keys(translations())

  def lookup(tree, locale, key, bindings, opts \\ []) do
    chain =
      if Keyword.get(opts, :fallback, true), do: Enum.uniq([locale, @default]), else: [locale]

    path = String.split(key, ".")

    Enum.find_value(chain, :missing, fn candidate ->
      case dig(tree, [candidate | path]) do
        nil -> nil
        entry -> resolve(entry, bindings)
      end
    end)
  end

  defp resolve(entry, bindings) do
    with {:ok, entry} <- pluralize(entry, bindings["count"]), do: interpolate(entry, bindings)
  end

  defp pluralize(%{} = entry, count) when is_integer(count) do
    key =
      cond do
        count == 0 and Map.has_key?(entry, "zero") -> "zero"
        count == 1 -> "one"
        true -> "other"
      end

    case Map.fetch(entry, key) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, {:invalid_pluralization, key}}
    end
  end

  defp pluralize(%{} = entry, count) when is_binary(count) do
    case Map.fetch(entry, "other") do
      {:ok, value} -> {:ok, value}
      :error -> {:error, {:invalid_pluralization, "other"}}
    end
  end

  defp pluralize(entry, _count), do: {:ok, entry}

  defp interpolate(text, bindings) when is_binary(text) do
    case Regex.run(@reserved_pattern, text) do
      [_, key] ->
        {:error, {:reserved_interpolation_key, key}}

      nil ->
        case for(
               [_, name] <- Regex.scan(@pattern, text),
               not Map.has_key?(bindings, name),
               do: name
             ) do
          [] ->
            {:ok,
             Regex.replace(@pattern, text, fn
               "%%", _ -> "%"
               _, name -> to_string(bindings[name])
             end)}

          [name | _] ->
            {:error, {:missing_interpolation, name}}
        end
    end
  end

  defp interpolate(list, bindings) when is_list(list) do
    Enum.reduce_while(list, {:ok, []}, fn element, {:ok, acc} ->
      case interpolate(element, bindings) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end
  end

  defp interpolate(entry, _bindings), do: {:ok, entry}

  defp dig(value, []), do: value
  defp dig(%{} = map, [key | rest]), do: map |> Map.get(key) |> dig(rest)
  defp dig(_value, _path), do: nil

  defp translations do
    case :persistent_term.get(__MODULE__, nil) do
      nil ->
        path =
          Application.get_env(
            :dawarich,
            :i18n_path,
            Dawarich.RailsRoot.join("tmp/phoenix/i18n.json")
          )

        tree =
          case File.read(path) do
            {:ok, json} ->
              Jason.decode!(json)

            {:error, reason} ->
              raise "cannot read #{path} (#{reason}); run mix dawarich.i18n"
          end

        :persistent_term.put(__MODULE__, tree)
        tree

      tree ->
        tree
    end
  end
end
