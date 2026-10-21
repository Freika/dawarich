defmodule Dawarich.RouteVideos.VideoMetadata do
  @moduledoc false

  def read(path, opts) do
    probe = Keyword.get(opts, :ffprobe, System.find_executable("ffprobe"))
    data = if probe, do: probe(probe, path), else: %{}
    streams = data["streams"] || []
    video = Enum.find(streams, %{}, &(&1["codec_type"] == "video"))
    angle = get_in(video, ["tags", "rotate"]) || rotation(video)
    angle = integer(angle)
    ratio = ratio(video["display_aspect_ratio"])
    width = number(video["width"])

    height =
      if width && ratio, do: width * List.last(ratio) / hd(ratio), else: number(video["height"])

    {width, height} = if angle in [90, 270, -90, -270], do: {height, width}, else: {width, height}

    %{
      "width" => width,
      "height" => height,
      "duration" => number(video["duration"] || get_in(data, ["format", "duration"])),
      "angle" => angle,
      "display_aspect_ratio" => ratio,
      "audio" => Enum.any?(streams, &(&1["codec_type"] == "audio")),
      "video" => video != %{}
    }
    |> Map.reject(fn {_, value} -> is_nil(value) end)
  end

  defp probe(executable, path) do
    task =
      Task.async(fn ->
        System.cmd(
          executable,
          ["-print_format", "json", "-show_streams", "-show_format", "-v", "quiet", path]
        )
      end)

    case Task.yield(task, 60_000) || Task.shutdown(task) do
      {:ok, {json, _status}} -> Jason.decode!(json)
      nil -> raise "route video analysis timed out"
    end
  end

  defp rotation(video),
    do:
      Enum.find(video["side_data_list"] || [], %{}, &(&1["side_data_type"] == "Display Matrix"))[
        "rotation"
      ]

  defp number(nil), do: nil
  defp number(n) when is_number(n), do: n / 1
  defp number(n), do: n |> Float.parse() |> elem(0)
  defp integer(nil), do: nil
  defp integer(n) when is_integer(n), do: n
  defp integer(n) when is_float(n), do: trunc(n)
  defp integer(n), do: String.to_integer(n)
  defp ratio(nil), do: nil

  defp ratio(value) do
    [numerator, denominator] =
      value |> String.split(":", parts: 2) |> Enum.map(&String.to_integer/1)

    if numerator != 0, do: [numerator, denominator]
  end
end
