defmodule Dawarich.UserData.Export.Zip do
  @moduledoc false
  alias Dawarich.Exports.Zip

  def write!(dir) do
    path = Path.join(dir, "export.zip")

    files =
      Path.wildcard(Path.join(dir, "**/*"))
      |> Enum.reject(&(File.dir?(&1) or &1 == path))
      |> Enum.sort()

    File.open!(path, [:write, :binary, :raw], fn out ->
      central = Enum.map(files, &Zip.write_entry!(out, &1, Path.relative_to(&1, dir)))
      {:ok, offset} = :file.position(out, :cur)

      :ok =
        :file.write(out, [central, Zip.trailer(offset, IO.iodata_length(central), length(files))])
    end)

    path
  end
end
