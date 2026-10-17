#!/bin/sh
grep -vE '^(--|SET |SELECT pg_catalog\.set_config|\\restrict |\\unrestrict )' | grep -v '^[[:space:]]*$' | awk '
skip_next { skip_next = 0; next }
/^ALTER TABLE ONLY public\.data_migrations$/ { skip_next = 1; next }
!in_table && /^CREATE TABLE .*\($/ {
  header = $0
  skip_tbl = (header ~ /public\.data_migrations \($/) ? 1 : 0
  in_table = 1
  n = 0
  if (!skip_tbl) print header
  next
}
in_table && /^\)/ {
  in_table = 0
  if (!skip_tbl) {
    for (i = 1; i <= n; i++) {
      line = lines[i]
      sub(/,$/, "", line)
      body[i] = line
    }
    for (i = 1; i <= n; i++) {
      for (j = i + 1; j <= n; j++) {
        if (body[j] < body[i]) {
          tmp = body[i]; body[i] = body[j]; body[j] = tmp
        }
      }
    }
    for (i = 1; i <= n; i++) {
      if (i < n) print body[i] ","
      else print body[i]
    }
    print $0
  }
  next
}
in_table { n++; lines[n] = $0; next }
{ print }
'
