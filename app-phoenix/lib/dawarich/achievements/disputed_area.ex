defmodule Dawarich.Achievements.DisputedArea.Geometry do
  @moduledoc false
  use Ecto.Type

  def type, do: :string
  def cast(%{coordinates: _, srid: 4326} = value), do: {:ok, value}
  def cast(_), do: :error
  def load(value) when is_binary(value), do: Geo.WKB.decode(value)
  def load(_), do: :error

  def dump(%{coordinates: _, srid: 4326} = value),
    do: {:ok, value |> Geo.WKB.encode_to_iodata() |> IO.iodata_to_binary() |> Base.encode16()}

  def dump(_), do: :error
end

defmodule Dawarich.Achievements.DisputedArea do
  @moduledoc false
  use Ecto.Schema

  schema "disputed_areas" do
    field :name, :string
    field :geom, Dawarich.Achievements.DisputedArea.Geometry, load_in_query: false
    timestamps(inserted_at: :created_at, type: :naive_datetime_usec)
  end

  def fetch!(repo, id) do
    [[id, name, geom, created, updated]] =
      repo.query!(
        "SELECT id,name,geom::text,created_at,updated_at FROM disputed_areas WHERE id=$1",
        [id],
        log: false
      ).rows

    repo.load(__MODULE__, %{
      "id" => id,
      "name" => name,
      "geom" => geom,
      "created_at" => created,
      "updated_at" => updated
    })
  end

  def covering_sql(geometry),
    do: "EXISTS (SELECT 1 FROM disputed_areas d WHERE ST_Intersects(d.geom, #{geometry}))"

  def near_cell_sql(gx, gy),
    do:
      "EXISTS (SELECT 1 FROM disputed_areas d WHERE d.geom && ST_MakeEnvelope(#{gx}*0.01,#{gy}*0.01,(#{gx}+1)*0.01,(#{gy}+1)*0.01,4326))"
end
