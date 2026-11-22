#!/bin/bash
# Self-check for templates/clamav-scan.sh.j2: renders it locally and runs it against stubbed
# clamscan/curl. Touches nothing outside a temp dir. Run from the repo root:
#   bash roles/clamav/tests/test-scan.sh
set -u
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/dl dir" "$T/opt"
EVIL="$T/dl dir/eicar \"q';@x.com"   # quotes, ';' and '@' in a file name
touch "$EVIL"

cat > "$T/bin/clamscan" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" > "$T/clamscan.args"
[ "$CLAM_RC" = 1 ] && echo "$EVIL: Eicar-Signature FOUND"
[ "$CLAM_RC" = 2 ] && echo "LibClamAV Error: cli_loaddbdir: no signatures"
exit "$CLAM_RC"
EOF
printf '#!/bin/bash\nprintf "%%s\\n" "$@" > "$T/curl.args"\n' > "$T/bin/curl"
printf '#!/bin/bash\nshift 2; exec "$@"\n' > "$T/bin/ionice"   # ionice -c 3 cmd...
printf '#!/bin/bash\n' > "$T/bin/logger"
chmod +x "$T"/bin/*
export T EVIL PATH="$T/bin:$PATH"

render() { # $1 = gotify enabled (true/false)
  ansible localhost -c local -m template -a "src=roles/clamav/templates/clamav-scan.sh.j2 dest=$T/scan.sh" \
    -e @roles/clamav/defaults/main.yml \
    -e "{\"clamav_scan_dirs\": [\"$T/dl dir\", \"$T/missing\", \"$T/opt\"], \"clamav_log_file\": \"$T/scan.log\",
         \"clamav_gotify_enabled\": $1, \"clamav_gotify_url\": \"http://gotify.test\", \"clamav_gotify_token\": \"tok\"}" \
    >/dev/null 2>&1 || { echo "FAIL: render"; exit 1; }
  bash -n "$T/scan.sh" || { echo "FAIL: bash -n"; exit 1; }
}
run() { rm -f "$T"/*.args; CLAM_RC=$1 bash "$T/scan.sh"; RC=$?; }
fail=0
ok() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }

render true
run 0
ok "clean: exit 0, no notification"        '[ $RC -eq 0 ] && [ ! -e "$T/curl.args" ]'
ok "existing dirs passed, missing skipped" 'grep -qxF "$T/dl dir" "$T/clamscan.args" && grep -qxF "$T/opt" "$T/clamscan.args" && ! grep -q missing "$T/clamscan.args"'
ok "excludes passed"                       'grep -qxF -- "--exclude-dir=^/opt/utility-stack/data/loki" "$T/clamscan.args"'
run 1
ok "infected: exit 1, priority 10"         '[ $RC -eq 1 ] && grep -qxF "priority=10" "$T/curl.args" && grep -q "^title=ClamAV: 1 infected" "$T/curl.args"'
ok "awkward file name sent literally"      'grep -qxF "message=$EVIL: Eicar-Signature FOUND" "$T/curl.args" && grep -qxF -- "--form-string" "$T/curl.args"'
ok "token in header, right URL"            'grep -qxF "X-Gotify-Key: tok" "$T/curl.args" && grep -qxF "http://gotify.test/message" "$T/curl.args"'
run 2
ok "error: exit 2, priority 8, error text" '[ $RC -eq 2 ] && grep -qxF "priority=8" "$T/curl.args" && grep -q "LibClamAV Error" "$T/curl.args"'
render false
run 1
ok "gotify disabled: no curl, logged"      '[ $RC -eq 1 ] && [ ! -e "$T/curl.args" ] && grep -q "Gotify not configured" "$T/scan.log"'
exit $fail
