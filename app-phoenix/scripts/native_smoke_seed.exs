r = Dawarich.Repo
[[id]] = r.query!("SELECT id FROM users WHERE email=$1", ["demo@dawarich.app"], log: false).rows

r.query!(
  "UPDATE users SET settings = settings || $1, api_key=$2 WHERE id=$3",
  [
    %{
      "timezone" => "UTC",
      "locale" => "en",
      "globe_projection" => false,
      "onboarding_completed" => true,
      "enabled_map_layers" => ["Points", "Tracks"]
    },
    System.fetch_env!("NATIVE_SMOKE_API_KEY"),
    id
  ],
  log: false
)

for {offset, lon, lat} <- [{0, 13.405, 52.52}, {60, 13.406, 52.521}, {120, 13.407, 52.522}] do
  r.query!(
    "INSERT INTO points(user_id,timestamp,lonlat,created_at,updated_at) VALUES($1,$2,ST_SetSRID(ST_MakePoint($3,$4),4326),now(),now())",
    [id, 1_760_529_600 + offset, lon, lat],
    log: false
  )
end

r.query!(
  "INSERT INTO tracks(user_id,start_at,end_at,distance,duration,original_path,created_at,updated_at) VALUES($1,'2025-10-15 12:00','2025-10-15 12:02',300,120,ST_GeomFromText('LINESTRING(13.405 52.52,13.406 52.521,13.407 52.522)',4326),now(),now())",
  [id],
  log: false
)

r.query!(
  "INSERT INTO stats(user_id,year,month,distance,daily_distance,created_at,updated_at) VALUES($1,2025,10,300,$2,now(),now())",
  [id, %{"2025-10-15" => 300}],
  log: false
)

r.query!(
  "INSERT INTO shared_links(id,user_id,resource_type,name,settings,created_at,updated_at) VALUES('00000000-0000-4000-8000-000000000004',$1,2,'Synthetic smoke',$2,now(),now())",
  [id, %{"start_date" => "2025-10-15", "end_date" => "2025-10-15"}],
  log: false
)

r.query!("UPDATE users SET points_count=3 WHERE id=$1", [id], log: false)
IO.puts("synthetic smoke data ready")
