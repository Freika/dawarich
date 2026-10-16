INSERT INTO regions(code,geom,created_at,updated_at)
SELECT code,ST_Multi(ST_MakeEnvelope(0,0,1,1,4326)),'2026-01-01','2026-01-01'
FROM unnest(ARRAY['UA-43','UA-40','DE-BE']) code;
