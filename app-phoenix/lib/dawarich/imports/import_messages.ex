defmodule Dawarich.Imports.ImportMessages do
  @moduledoc false
  alias Dawarich.I18n
  @prefix "services.imports.create."

  def failure(import, context, error, stacktrace \\ []) do
    content =
      if Map.get(context, :self_hosted?, true) do
        frames = Enum.map_join(stacktrace, "\n", &frame/1)

        translate(context, "import_failed_self_hosted", %{
          "name" => import.name,
          "message" => Exception.message(error),
          "backtrace" => frames
        })
      else
        translate(context, "import_failed_cloud", %{"name" => import.name})
      end

    %{kind: :error, title: translate(context, "import_failed"), content: content}
  end

  def post_failure(import, context, step) do
    %{
      kind: :warning,
      title: translate(context, "import_post_processing_incomplete"),
      content:
        translate(context, "your_import_name_finished_and_all_points_were_saved_but", %{
          "name" => import.name,
          "step" => String.replace(step, "_", " ")
        })
    }
  end

  def zero(import, context) do
    if (import.doubles || 0) > 0 do
      %{
        kind: :info,
        title: translate(context, "import_completed_with_no_new_points"),
        content:
          translate(context, "your_file_name_contained_raw_points_points_all_of_which", %{
            "name" => import.name,
            "raw_points" => import.raw_points
          })
      }
    else
      %{
        kind: :warning,
        title: translate(context, "import_completed_with_no_points"),
        content: zero_content(import, context)
      }
    end
  end

  defp zero_content(import, context) do
    data = import.raw_data || %{}
    bindings = %{"name" => import.name}

    cond do
      integer(data["trackpoints_seen"]) == 0 and integer(data["waypoints_seen"]) > 0 ->
        translate(
          context,
          "zero_points_waypoints_only",
          Map.put(bindings, "count", integer(data["waypoints_seen"]))
        )

      integer(data["trackpoints_seen"]) == 0 and integer(data["route_points_seen"]) > 0 ->
        translate(
          context,
          "zero_points_route_only",
          Map.put(bindings, "count", integer(data["route_points_seen"]))
        )

      import.source in [4, 6, 9] ->
        translate(context, "zero_points_with_timestamps", bindings)

      true ->
        translate(context, "zero_points", bindings)
    end
  end

  defp translate(context, key, bindings \\ %{}) do
    {:ok, text} = I18n.t(context.locale, @prefix <> key, bindings)
    text
  end

  defp integer(value) when is_integer(value), do: value

  defp integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, _} -> number
      :error -> 0
    end
  end

  defp integer(_), do: 0
  defp frame(value) when is_binary(value), do: value
  defp frame(value), do: Exception.format_stacktrace_entry(value)
end
