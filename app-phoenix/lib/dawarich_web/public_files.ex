defmodule DawarichWeb.PublicFiles do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  require Record

  alias Dawarich.RailsSecret
  alias DawarichWeb.{ForceSSL, Origin, RackScheme}

  Record.defrecordp(:file_info, Record.extract(:file_info, from_lib: "kernel/include/file.hrl"))

  @env ~w(RAILS_ENV RACK_ENV APPLICATION_HOSTS APPLICATION_PROTOCOL)
  @serving_envs ~w(production staging)
  @types %{
    "" => nil,
    ".bin" => "application/octet-stream",
    ".css" => "text/css",
    ".gif" => "image/gif",
    ".html" => "text/html",
    ".ico" => "image/vnd.microsoft.icon",
    ".jpeg" => "image/jpeg",
    ".jpg" => "image/jpeg",
    ".js" => "text/javascript",
    ".json" => "application/json",
    ".map" => nil,
    ".mjs" => "text/javascript",
    ".pmtiles" => nil,
    ".png" => "image/png",
    ".svg" => "image/svg+xml",
    ".ttf" => "font/ttf",
    ".txt" => "text/plain",
    ".webmanifest" => "application/manifest+json",
    ".webp" => "image/webp",
    ".woff" => "font/woff",
    ".woff2" => "font/woff2"
  }
  @compressible ~r/\A(?:text\/|application\/javascript|image\/svg\+xml)/
  @encodings [{"br", ".br", ~r/\bbr\b/i}, {"gzip", ".gz", ~r/\bgzip\b/i}]

  def content_types, do: @types

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%{method: method} = conn, opts) when method in ["GET", "HEAD"] do
    env = Keyword.get_lazy(opts, :env, fn -> Map.new(@env, &{&1, System.get_env(&1)}) end)
    root = Keyword.get_lazy(opts, :root, &default_root/0)

    with true <- RailsSecret.rails_env(env) in @serving_envs,
         [] <- get_req_header(conn, "range"),
         {:ok, segments} <- segments(conn.request_path),
         {path, info, headers} <- find(root, segments, header(conn, "accept-encoding") || ""),
         true <- authorized?(conn, env["APPLICATION_HOSTS"]),
         {:ok, secure} <- secure_headers(conn, env) do
      respond(conn, path, info, headers, secure)
    else
      _ -> conn
    end
  end

  def call(conn, _opts), do: conn

  defp default_root,
    do: Application.get_env(:dawarich, :public_root) || Path.join(File.cwd!(), "public")

  defp header(conn, name) do
    case get_req_header(conn, name) do
      [] -> nil
      values -> Enum.join(values, ", ")
    end
  end

  defp authorized?(conn, application_hosts) do
    case get_req_header(conn, "host") do
      [host] ->
        [host | List.wrap(forwarded_host(conn))]
        |> Enum.all?(&Origin.authorized_host?(&1, application_hosts))

      _ ->
        false
    end
  end

  defp forwarded_host(conn) do
    with value when is_binary(value) <- header(conn, "x-forwarded-host"),
         do: value |> String.split(~r/,\s?/, trim: true) |> List.last()
  end

  defp secure_headers(conn, env) do
    cond do
      not ForceSSL.enabled?(env) -> {:ok, []}
      RackScheme.ssl?(conn) -> {:ok, [{"strict-transport-security", ForceSSL.hsts()}]}
      true -> :redirect
    end
  end

  defp segments(request_path) do
    case request_path |> String.replace_suffix("/", "") |> URI.decode() |> String.split("/") do
      ["" | [_ | _] = segments] ->
        if Enum.all?(segments, &plain_segment?/1), do: {:ok, segments}, else: :error

      _ ->
        :error
    end
  end

  defp plain_segment?(segment), do: segment != "" and not String.starts_with?(segment, ".")

  defp find(root, segments, accept) do
    {dirs, [name]} = Enum.split(segments, -1)

    with {:ok, dir} <- walk(root, dirs),
         {:ok, type} <- Map.fetch(@types, String.downcase(Path.extname(name))) do
      Enum.find_value(candidates(name, type), fn {subdirs, file, type} ->
        case walk(dir, subdirs) do
          {:ok, subdir} -> try_file(Path.join(subdir, file), type, accept)
          :error -> nil
        end
      end)
    end
  end

  defp candidates(name, nil),
    do: [
      {[], name, "text/plain"},
      {[], name <> ".html", "text/html"},
      {[name], "index.html", "text/html"}
    ]

  defp candidates(name, type), do: [{[], name, type}]

  defp walk(dir, []), do: {:ok, dir}

  defp walk(dir, [name | rest]) do
    path = Path.join(dir, name)

    case :prim_file.read_link_info(path) do
      {:ok, file_info(type: :directory)} -> walk(path, rest)
      _ -> :error
    end
  end

  defp try_file(path, type, accept) do
    if type =~ @compressible,
      do: precompressed(path, type, accept),
      else: plain(path, [{"content-type", type}])
  end

  defp precompressed(path, type, accept) do
    @encodings
    |> Enum.reduce_while([{"content-type", type}], &variant(path, accept, &1, &2))
    |> case do
      {_, _, _} = found -> found
      headers -> plain(path, headers)
    end
  end

  defp variant(path, accept, {encoding, extension, pattern}, headers) do
    case regular(path <> extension) do
      nil ->
        {:cont, headers}

      info ->
        headers = List.keystore(headers, "vary", 0, {"vary", "accept-encoding"})

        if accepts?(accept, pattern),
          do: {:halt, {path <> extension, info, [{"content-encoding", encoding} | headers]}},
          else: {:cont, headers}
    end
  end

  defp plain(path, headers) do
    if info = regular(path), do: {path, info, headers}
  end

  defp regular(path) do
    case :prim_file.read_link_info(path, [{:time, :posix}]) do
      {:ok, file_info(type: :regular, access: access) = info}
      when access in [:read, :read_write] ->
        info

      _ ->
        nil
    end
  end

  defp accepts?(accept, pattern),
    do: accept |> String.split(",") |> Enum.any?(&(coding(&1) =~ pattern))

  defp coding(part), do: part |> String.split(";", parts: 2) |> hd()

  defp respond(conn, path, file_info(size: size, mtime: mtime), headers, secure) do
    last_modified = Calendar.strftime(DateTime.from_unix!(mtime), "%a, %d %b %Y %H:%M:%S GMT")

    if header(conn, "if-modified-since") == last_modified do
      %{conn | resp_headers: [{"content-length", "0"} | secure]} |> send_resp(304, "") |> halt()
    else
      resp_headers =
        [{"last-modified", last_modified}, {"content-length", "#{size}"} | headers] ++ secure

      %{conn | resp_headers: resp_headers} |> send_file(200, path) |> halt()
    end
  end
end
