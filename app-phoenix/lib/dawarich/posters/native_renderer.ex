defmodule Dawarich.Posters.NativeRenderer do
  @moduledoc false
  alias Dawarich.{RailsRoot, Storage}
  alias Dawarich.Posters.Geometry
  alias Dawarich.Ingest.Ruby
  @timeout 180_000
  @terminate 5_000
  @output_limit 16_384

  defmodule Error do
    defexception [:message]
  end

  def render(poster, track, locale, opts \\ []) do
    root = Keyword.get(opts, :temp_root, System.tmp_dir!())
    dir = Storage.tmp_dir!(%{root: root}, "poster-render-" <> Storage.generate_key())
    png = Path.join(dir, "poster.png")
    pdf = Path.join(dir, "poster.pdf")

    try do
      path = Path.join(dir, "job.json")
      File.write!(path, Jason.encode!(payload(poster, track, locale, png, pdf)))
      run(Keyword.get_lazy(opts, :command, &command/0), path, opts)
      %{png: File.read!(png), pdf: File.read!(pdf)}
    rescue
      e in File.Error -> raise Error, "Poster renderer output missing: #{e.reason}"
    after
      File.rm_rf!(dir)
    end
  end

  defp payload(poster, track, locale, png, pdf) do
    settings = poster.settings
    theme = settings |> Map.get("theme", "terracotta") |> Ruby.to_s() |> Path.basename()
    path = RailsRoot.join("public/poster_themes/#{theme}.json")
    unless File.exists?(path), do: raise(Error, "Unknown poster theme #{inspect(theme)}")
    tokens = path |> File.read!() |> Jason.decode!()

    %{
      tokens: tokens,
      trackGeojson: %{type: "Feature", properties: %{}, geometry: track},
      trackOpacity: Geometry.opacity(settings),
      trackWidth: Geometry.width(settings),
      view: %{
        lat: Ruby.to_f(settings["lat"]),
        lon: Ruby.to_f(settings["lon"]),
        distance: Geometry.distance(settings)
      },
      size: %{width: 1200, height: 1600, ratio: 2},
      text: %{
        title: Map.get(settings, "title", poster.name),
        subtitle: Geometry.subtitle(settings, locale),
        coords: true
      },
      output: %{png: png, pdf: pdf, widthMm: 300, heightMm: 400, dpi: 203}
    }
  end

  defp command do
    case System.get_env("POSTER_RENDERER_CMD") do
      value when is_binary(value) ->
        if Ruby.blank?(value),
          do: [RailsRoot.join("vendor/poster_renderer/render.sh")],
          else: String.split(value)

      nil ->
        [RailsRoot.join("vendor/poster_renderer/render.sh")]
    end
  end

  defp run([executable | args], job, opts) do
    executable =
      System.find_executable(executable) || raise(Error, "Poster renderer executable missing")

    port =
      Port.open({:spawn_executable, executable}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: args ++ [job]
      ])

    {:os_pid, pid} = Port.info(port, :os_pid)
    timeout = Keyword.get(opts, :timeout_ms, @timeout)

    try do
      if observer = opts[:on_spawn], do: observer.(port)
      deadline = System.monotonic_time(:millisecond) + timeout

      case await(port, deadline, opts, "") do
        {0, _} -> :ok
        {status, output} -> raise Error, "Poster renderer failed (#{status}): #{output}"
        :timeout -> raise Error, "Poster renderer timed out after #{timeout} ms"
      end
    after
      cleanup(port, pid, opts)
    end
  end

  defp await(port, deadline, opts, output) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      :timeout
    else
      receive do
        {^port, {:data, data}} ->
          if observer = opts[:on_output], do: observer.(data)
          await(port, deadline, opts, diagnostics(output, data))

        {^port, {:exit_status, status}} ->
          {status, output}
      after
        remaining -> :timeout
      end
    end
  end

  defp diagnostics(output, data) do
    combined = output <> data
    size = byte_size(combined)
    binary_part(combined, max(size - @output_limit, 0), min(size, @output_limit))
  end

  defp cleanup(port, pid, opts) do
    try do
      if alive?(pid, opts) do
        case signal("-TERM", pid, opts) do
          {_, 0} ->
            deadline =
              System.monotonic_time(:millisecond) + Keyword.get(opts, :terminate_ms, @terminate)

            _ = await(port, deadline, opts, "")
            if alive?(pid, opts), do: kill!(pid, opts)

          {_, _} ->
            kill!(pid, opts)
        end
      end
    after
      if Port.info(port), do: Port.close(port)
    end
  end

  defp alive?(pid, opts), do: elem(kill_command(["-0", "--", "-#{pid}"], opts), 1) == 0

  defp signal(signal, pid, opts) do
    if observer = opts[:on_signal], do: observer.(signal, pid)

    case kill_command([signal, "--", "-#{pid}"], opts) do
      {_, 0} = result -> result
      {output, _} = result -> if alive?(pid, opts), do: result, else: {output, 0}
    end
  end

  defp kill!(pid, opts) do
    case signal("-KILL", pid, opts) do
      {_, 0} -> :ok
      {output, status} -> raise Error, "Poster renderer group KILL failed (#{status}): #{output}"
    end
  end

  defp kill_command(args, opts),
    do:
      Keyword.get(opts, :kill_command, &System.cmd/3).("/bin/kill", args, stderr_to_stdout: true)
end
