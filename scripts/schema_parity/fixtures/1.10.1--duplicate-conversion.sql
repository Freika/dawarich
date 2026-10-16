INSERT INTO users(email,points_count,created_at,updated_at)
VALUES('duplicate-conversion@example.test',4,'2026-01-01','2026-01-01');
INSERT INTO points(user_id,timestamp,lonlat,latitude,longitude,raw_data,created_at,updated_at)
SELECT id,100,ST_SetSRID(ST_MakePoint(1,2),4326),NULL,NULL,'{}','2026-01-01','2026-01-01'
FROM users WHERE email='duplicate-conversion@example.test';
INSERT INTO points(user_id,timestamp,lonlat,latitude,longitude,raw_data,created_at,updated_at)
SELECT id,100,NULL,2,1,'{"source":"first"}','2026-01-01','2026-01-01'
FROM users WHERE email='duplicate-conversion@example.test';
INSERT INTO points(user_id,timestamp,lonlat,latitude,longitude,raw_data,created_at,updated_at)
SELECT id,100,NULL,2,1,'{"source":"second"}','2026-01-01','2026-01-01'
FROM users WHERE email='duplicate-conversion@example.test';
