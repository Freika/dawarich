INSERT INTO countries(name,iso_a2,iso_a3,geom,created_at,updated_at)
SELECT code,code,code,ST_Multi(ST_MakeEnvelope(0,0,1,1,4326)),'2026-01-01','2026-01-01'
FROM unnest(ARRAY['UA','RU','DE']) code;
