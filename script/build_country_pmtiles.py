#!/usr/bin/env python3
"""Build the bundled Visited Countries PMTiles archive deterministically.

Install the pinned dependencies from script/country_pmtiles_requirements.txt.
"""

import argparse
import gzip
import hashlib
import json
from pathlib import Path

import mapbox_vector_tile
import mercantile
from pmtiles.tile import Compression, TileType, zxy_to_tileid
from pmtiles.writer import Writer
from shapely.geometry import box, mapping, shape


def arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--maxzoom", type=int, default=6)
    return parser.parse_args()


def source_bytes(source):
    raw = source.read_bytes()
    return gzip.decompress(raw) if source.suffix == ".gz" else raw


def load_features(source):
    document = json.loads(source_bytes(source))
    result = []
    for feature in document["features"]:
        properties = feature["properties"]
        iso_a3 = properties.get("ISO3166-1-Alpha-3")
        name = properties.get("name") or properties.get("NAME")
        if not iso_a3 or not name:
            continue
        geometry = shape(feature["geometry"])
        result.append((iso_a3, name, geometry))
    return sorted(result, key=lambda item: item[0])


def encoded_tile(features, tile):
    bounds = mercantile.bounds(tile)
    tile_box = box(bounds.west, bounds.south, bounds.east, bounds.north)
    tolerance = (bounds.east - bounds.west) / 4096
    encoded = []
    for iso_a3, name, geometry in features:
        if not geometry.intersects(tile_box):
            continue
        clipped = geometry.intersection(tile_box).simplify(tolerance, preserve_topology=True)
        if clipped.is_empty:
            continue
        encoded.append(
            {
                "geometry": mapping(clipped),
                "properties": {"iso_a3": iso_a3, "name": name},
            }
        )
    if not encoded:
        return None
    payload = mapbox_vector_tile.encode(
        {"name": "countries", "features": encoded},
        default_options={
            "quantize_bounds": (bounds.west, bounds.south, bounds.east, bounds.north),
            "extents": 4096,
            "on_invalid_geometry": mapbox_vector_tile.encoder.on_invalid_geometry_make_valid,
        },
    )
    return gzip.compress(payload, compresslevel=9, mtime=0)


def build(source, output, maxzoom):
    features = load_features(source)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("wb") as stream:
        writer = Writer(stream)
        for zoom in range(maxzoom + 1):
            for tile in mercantile.tiles(-180, -85.05112878, 180, 85.05112878, zooms=zoom):
                data = encoded_tile(features, tile)
                if data:
                    writer.write_tile(zxy_to_tileid(tile.z, tile.x, tile.y), data)

        writer.finalize(
            {
                "tile_type": TileType.MVT,
                "tile_compression": Compression.GZIP,
                "min_lon_e7": -1_800_000_000,
                "min_lat_e7": -850_511_287,
                "max_lon_e7": 1_800_000_000,
                "max_lat_e7": 850_511_287,
                "center_lon_e7": 0,
                "center_lat_e7": 0,
                "center_zoom": 1,
            },
            {
                "name": "Dawarich country boundaries",
                "version": "1",
                "vector_layers": [
                    {
                        "id": "countries",
                        "fields": {"iso_a3": "String", "name": "String"},
                        "minzoom": 0,
                        "maxzoom": maxzoom,
                    }
                ],
                "source_sha256": hashlib.sha256(source_bytes(source)).hexdigest(),
            },
        )


if __name__ == "__main__":
    args = arguments()
    build(args.source, args.output, args.maxzoom)
