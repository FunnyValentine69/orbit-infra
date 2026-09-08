# Reproducible lease lifecycle demo. Rendered by demo/record.sh; do not run directly.
Output demo/out/demo.gif
Output demo/out/demo.txt
Set Shell "bash"
Set FontSize 16
Set Width 1200
Set Height 640
Set Framerate 20
Set TypingSpeed 40ms
Set Padding 20
Set WaitTimeout 20m

Hide
Type `record_rc() { echo "$?" > "$RUN/$1.rc"; }` Enter Wait
Type `set -o pipefail; env | grep -c '^RUN=' > "$RUN/env.ok"; clear` Enter Wait
Type `clear` Enter Wait
Show

# DEMO-SECTION lease-before
Hide
Type `lease_rc=0; scripts/lease.sh get "$ENV_ID" > "$RUN/lease-before.raw" 2> "$RUN/lease-before.err" || lease_rc=$?; if [ "$lease_rc" -eq 0 ]; then jq -r '"status=" + .status + " generation=" + (.generation|tostring)' "$RUN/lease-before.raw" > "$RUN/lease-before.log"; jq -r '.generation + 1' "$RUN/lease-before.raw" > "$RUN/lease.expected"; elif [ "$lease_rc" -eq 1 ] && grep -Fxq "lease.sh: no lease for $ENV_ID" "$RUN/lease-before.err"; then echo 'status=absent generation=0' > "$RUN/lease-before.log"; echo 1 > "$RUN/lease.expected"; lease_rc=0; fi; (exit "$lease_rc"); record_rc lease-before` Enter Wait
Type `clear` Enter Wait
Show
Type `cat "$RUN/lease-before.log"` Enter Wait
Sleep 2.5s

# DEMO-SECTION lease-open
Hide
Type `open_rc=0; scripts/lease.sh open "$ENV_ID" --owner "$DEMO_OWNER" > "$RUN/open.raw" || open_rc=$?; if [ "$open_rc" -eq 0 ]; then jq -r '.generation' "$RUN/open.raw" > "$RUN/lease.generation"; test "$(cat "$RUN/lease.generation")" = "$(cat "$RUN/lease.expected")" || open_rc=$?; jq -r '"status=" + .status + " generation=" + (.generation|tostring)' "$RUN/open.raw" > "$RUN/open.log"; fi; (exit "$open_rc"); record_rc lease-open` Enter Wait
Type `clear` Enter Wait
Show
Type `cat "$RUN/open.log"` Enter Wait
Sleep 2.5s

# DEMO-SECTION apply
Hide
Type `apply_rc=0; make plan > "$RUN/plan.log" 2>&1 || apply_rc=$?; if [ "$apply_rc" -eq 0 ]; then make apply > "$RUN/apply.log" 2>&1 || apply_rc=$?; fi; (exit "$apply_rc"); record_rc apply` Enter Wait
Type `clear` Enter Wait
Show
Type `grep -E '^Plan:' "$RUN/plan.log"; grep -E 'Apply complete' "$RUN/apply.log"` Enter Wait
Sleep 3s

# DEMO-SECTION lease-active
Hide
Type `make lease-get > "$RUN/lease-active.log" 2>&1; record_rc lease-active` Enter Wait
Type `clear` Enter Wait
Show
Type `grep -F '"status": "open"' "$RUN/lease-active.log"` Enter Wait
Sleep 2.5s

# DEMO-SECTION close
Hide
Type `scripts/close-env.sh "$ENV_ID" --owner "$DEMO_OWNER" --generation "$(cat "$RUN/lease.generation")" --from open > "$RUN/close.log" 2>&1; record_rc close` Enter Wait
Type `clear` Enter Wait
Show
Type `tail -n 1 "$RUN/close.log"` Enter Wait
Sleep 3s

# DEMO-SECTION sweep
Hide
Type `scripts/lease-sweep-until-closed.sh "$ENV_ID" --owner "$DEMO_OWNER" --generation "$(cat "$RUN/lease.generation")" > "$RUN/sweep.log" 2>&1; record_rc sweep` Enter Wait
Type `clear` Enter Wait
Show
Type `grep -E 'Stage 2 complete; lease is closed|^final_status=closed$' "$RUN/sweep.log"` Enter Wait
Sleep 3s
