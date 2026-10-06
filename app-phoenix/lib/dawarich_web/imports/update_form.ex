defmodule DawarichWeb.Imports.UpdateForm do
  @moduledoc false
  @keys ~w(authenticity_token _method trust_source import_id commit)
  @import_keys ~w(name source)

  def field?({"import", %{} = import}), do: Enum.all?(import, &import_field?/1)
  def field?({key, value}), do: key in @keys and is_binary(value)

  defp import_field?({"files", files}) when is_list(files), do: Enum.all?(files, &is_binary/1)
  defp import_field?({key, value}), do: key in @import_keys and is_binary(value)
end
