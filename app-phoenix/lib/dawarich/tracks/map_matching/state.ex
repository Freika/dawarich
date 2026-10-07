defmodule Dawarich.Tracks.MapMatching.State do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  embedded_schema do
    field :status, Ecto.Enum,
      values: [pending: 0, matched: 1, partial: 2, rejected: 3, skipped: 4, failed: 5]

    field :digest, :string
    field :data, :map, default: %{}
    field :matched_at, :utc_datetime_usec
    field :matched_path, :any, virtual: true
  end

  @columns [
    matched_path: "matched_path",
    status: "map_matching_status",
    digest: "map_matching_input_digest",
    data: "map_matching_data",
    matched_at: "map_matched_at"
  ]

  def write!(repo, track_id, attrs) do
    Enum.each(Map.keys(attrs), &Keyword.fetch!(@columns, &1))
    fields = Enum.filter(@columns, &Map.has_key?(attrs, elem(&1, 0)))

    if fields != [] do
      assignments =
        fields
        |> Enum.with_index(2)
        |> Enum.map_join(",", fn {{key, column}, index} ->
          expression =
            if key == :matched_path, do: "ST_GeomFromEWKB($#{index})", else: "$#{index}"

          "#{column}=#{expression}"
        end)

      params = [track_id | Enum.map(fields, fn {key, _} -> dump(key, Map.fetch!(attrs, key)) end)]
      repo.query!("UPDATE tracks SET #{assignments} WHERE id=$1", params, log: false)
    end

    :ok
  end

  def read(repo, track_id) do
    case repo.query!(
           """
           SELECT map_matching_status,map_matching_input_digest,map_matching_data,
             ST_AsEWKB(matched_path),map_matched_at FROM tracks WHERE id=$1
           """,
           [track_id],
           log: false
         ).rows do
      [[status, digest, data, path, stamp]] ->
        {:ok, status} = Ecto.Type.load(__schema__(:type, :status), status)

        %{
          status: status,
          digest: digest,
          data: data,
          matched_path: if(path, do: Geo.WKB.decode!(path)),
          matched_at: if(stamp, do: DateTime.from_naive!(stamp, "Etc/UTC"))
        }

      [] ->
        nil
    end
  end

  def result?(%{status: status}), do: status in [:matched, :partial]

  defp dump(_, nil), do: nil

  defp dump(:matched_path, %Geo.MultiLineString{srid: 4326} = path),
    do: path |> Geo.WKB.encode_to_iodata() |> IO.iodata_to_binary()

  defp dump(:matched_at, %DateTime{} = stamp),
    do: stamp |> DateTime.shift_zone!("Etc/UTC") |> DateTime.to_naive()

  defp dump(:matched_at, %NaiveDateTime{} = stamp), do: stamp

  defp dump(:status, status) do
    {:ok, integer} = Ecto.Type.dump(__schema__(:type, :status), status)
    integer
  end

  defp dump(_, value), do: value
end
