defmodule Dawarich.Build.I18n do
  @moduledoc false

  alias Dawarich.Build.Yaml
  alias Jason.OrderedObject

  @locales ~w(en de es fr pl ca zh)

  def locales, do: @locales

  def export(root), do: root |> tree() |> Jason.encode_to_iodata!()

  def tree(root) do
    files = root |> Path.join("config/locales/**/*.{rb,yml}") |> Path.wildcard() |> Enum.sort()

    case Enum.filter(files, &String.ends_with?(&1, ".rb")) do
      [] ->
        :ok

      ruby ->
        raise ArgumentError, "Ruby locale files cannot be exported: #{Enum.join(ruby, ", ")}"
    end

    merged = Enum.reduce(files, [], &merge_file/2)
    %OrderedObject{values: Enum.flat_map(@locales, &List.wrap(List.keyfind(merged, &1, 0)))}
  end

  def deep_merge(%OrderedObject{values: left}, %OrderedObject{values: right}) do
    values =
      Enum.reduce(right, left, fn {key, value}, acc ->
        merged =
          case List.keyfind(acc, key, 0) do
            {_, %OrderedObject{} = existing} when is_struct(value, OrderedObject) ->
              deep_merge(existing, value)

            _ ->
              value
          end

        List.keystore(acc, key, 0, {key, merged})
      end)

    %OrderedObject{values: values}
  end

  defp merge_file(file, acc) do
    case Yaml.load!(file) do
      %OrderedObject{values: locales} -> Enum.reduce(locales, acc, &store(&1, &2, file))
      _ -> raise ArgumentError, "#{file} must map locales to translations"
    end
  end

  defp store({locale, _tree}, acc, _file) when locale not in @locales, do: acc

  defp store({locale, tree}, acc, file) do
    tree = tree || %OrderedObject{values: []}

    unless is_struct(tree, OrderedObject),
      do: raise(ArgumentError, "#{file}: #{locale} is not a mapping")

    current =
      case List.keyfind(acc, locale, 0) do
        {_, existing} -> existing
        nil -> %OrderedObject{values: []}
      end

    List.keystore(acc, locale, 0, {locale, deep_merge(current, tree)})
  end
end
