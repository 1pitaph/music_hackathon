from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import sqlite3
from typing import Any

from radio_agent.api import (
  _discover_db_connection,
  _discover_db_path,
  _discover_storage_status,
  _ensure_discover_schema,
  _station_from_payload_json,
)
from radio_agent.schemas import DiscoverStationResponse


def main(argv: list[str] | None = None) -> int:
  parser = argparse.ArgumentParser(description="Inspect, back up, export, or import Airset discover stations.")
  parser.add_argument("--db-path", help="Override DISCOVER_STATIONS_DB_PATH for this command.")
  subparsers = parser.add_subparsers(dest="command", required=True)

  subparsers.add_parser("status", help="Print JSON storage status.")

  backup_parser = subparsers.add_parser("backup", help="Create a consistent SQLite backup.")
  backup_parser.add_argument("output", help="Destination SQLite backup path.")

  export_parser = subparsers.add_parser("export", help="Export discover station payloads to JSON.")
  export_parser.add_argument("output", help="Destination JSON path.")

  import_parser = subparsers.add_parser("import", help="Import discover station payloads from JSON.")
  import_parser.add_argument("input", help="Source JSON path.")

  args = parser.parse_args(argv)
  if args.db_path:
    os.environ["DISCOVER_STATIONS_DB_PATH"] = args.db_path

  if args.command == "status":
    _print_json(_discover_storage_status().model_dump(mode="json"))
    return 0
  if args.command == "backup":
    _backup(Path(args.output))
    return 0
  if args.command == "export":
    _export(Path(args.output))
    return 0
  if args.command == "import":
    _import(Path(args.input))
    return 0

  parser.error(f"Unknown command: {args.command}")
  return 2


def _backup(output_path: Path) -> None:
  db_path = _discover_db_path()
  if db_path == ":memory:":
    raise SystemExit("Cannot back up an in-memory discover database.")
  if not Path(db_path).is_file():
    raise SystemExit(f"Discover database does not exist: {db_path}")

  output_path.parent.mkdir(parents=True, exist_ok=True)
  source = sqlite3.connect(db_path)
  destination = sqlite3.connect(output_path)
  try:
    source.backup(destination)
  finally:
    destination.close()
    source.close()


def _export(output_path: Path) -> None:
  connection = _discover_db_connection()
  try:
    _ensure_discover_schema(connection)
    rows = connection.execute(
      """
      SELECT payload_json FROM discover_stations
      ORDER BY published_at DESC, station_id DESC
      """
    ).fetchall()
  finally:
    connection.close()

  payload = {
    "exportedAt": datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
    "dbPath": _discover_db_path(),
    "stations": [
      _station_from_payload_json(row["payload_json"]).model_dump(mode="json")
      for row in rows
    ],
  }
  output_path.parent.mkdir(parents=True, exist_ok=True)
  output_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True), encoding="utf-8")


def _import(input_path: Path) -> None:
  payload = json.loads(input_path.read_text(encoding="utf-8"))
  station_payloads = payload.get("stations", payload)
  if not isinstance(station_payloads, list):
    raise SystemExit("Import JSON must be a list or an object with a stations list.")

  stations = [DiscoverStationResponse.model_validate(item) for item in station_payloads]
  connection = _discover_db_connection()
  try:
    _ensure_discover_schema(connection)
    for station in stations:
      _upsert_station(connection, station)
    connection.commit()
  finally:
    connection.close()


def _upsert_station(connection: sqlite3.Connection, station: DiscoverStationResponse) -> None:
  payload_json = json.dumps(station.model_dump(mode="json"), ensure_ascii=False)
  connection.execute(
    """
    INSERT INTO discover_stations (
      station_id,
      visibility,
      owner_id,
      owner_display_name,
      client_publication_id,
      published_at,
      share_url,
      payload_json
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(station_id) DO UPDATE SET
      visibility = excluded.visibility,
      owner_id = excluded.owner_id,
      owner_display_name = excluded.owner_display_name,
      client_publication_id = excluded.client_publication_id,
      published_at = excluded.published_at,
      share_url = excluded.share_url,
      payload_json = excluded.payload_json
    """,
    (
      station.stationID,
      station.visibility,
      station.ownerID,
      station.ownerDisplayName,
      station.clientPublicationID,
      station.publishedAt,
      station.shareURL,
      payload_json,
    ),
  )


def _print_json(value: dict[str, Any]) -> None:
  print(json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True))


if __name__ == "__main__":
  raise SystemExit(main())
