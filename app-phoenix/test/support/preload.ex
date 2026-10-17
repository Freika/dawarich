defmodule Dawarich.Test.Preload do
  @moduledoc false

  def modules, do: Enum.flat_map(applications(), &List.wrap(Application.spec(&1, :modules)))

  def load!, do: Code.ensure_all_loaded!(modules())

  defp applications, do: closure([:dawarich, :ex_unit], [])

  defp closure([], seen), do: seen

  defp closure([app | rest], seen) do
    if app in seen do
      closure(rest, seen)
    else
      children =
        List.wrap(Application.spec(app, :applications)) ++
          List.wrap(Application.spec(app, :included_applications))

      closure(children ++ rest, [app | seen])
    end
  end
end
