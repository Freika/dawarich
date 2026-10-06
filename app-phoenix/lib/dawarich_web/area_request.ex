defmodule DawarichWeb.AreaRequest do
  @moduledoc false
  def target(_), do: nil
  def action(action, _), do: action
  def fields?(_, _), do: false
  def query(%{query_string: ""}), do: {:ok, %{}}
  def query(_), do: :replay
  def format(_, _), do: :replay
end
