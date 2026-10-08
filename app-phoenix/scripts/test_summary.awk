# ExUnit <= 1.19 and >= 1.20 summaries; failure status also comes from Mix's exit code.
/^[0-9]+ tests?, [0-9]+ failures?/ { tests += $1; failures += $3 }
/^Result: / {
  n = split($2, counts, "/")
  if (n == 2) { tests += counts[2]; failures += counts[2] - counts[1] }
  else { tests += counts[1] }
}
END { printf "%d tests, %d failures\n", tests, failures; exit failures != 0 }
