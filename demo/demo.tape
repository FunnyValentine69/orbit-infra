# Reproducible LocalStack demo. Rendered by demo/record.sh via `make demo`; do not run directly.
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
Type `set -o pipefail; env | grep -c '^RUN=' > "$RUN/env.ok"; clear` Enter Wait
Show

# DEMO-SECTION status
Type `make localstack-status 2>&1 | head -n 14 || printf 'DEMO-%s\n' FAIL` Enter Wait
Sleep 2.5s

# DEMO-SECTION plan
Hide
Type `make plan > "$RUN/plan.log" 2>&1; echo $? > "$RUN/plan.rc"` Enter Wait
Show
Type `grep -E '^Plan:' "$RUN/plan.log" || printf 'DEMO-%s\n' FAIL` Enter Wait
Sleep 2.5s
Type `make conftest 2>&1 | tail -n 3 || printf 'DEMO-%s\n' FAIL` Enter Wait
Sleep 2.5s
Hide
Type `clear` Enter Wait
Show

# DEMO-SECTION apply
Hide
Type `make apply > "$RUN/apply.log" 2>&1; echo $? > "$RUN/apply.rc"` Enter Wait
Show
Type `grep -E 'Apply complete' "$RUN/apply.log" || printf 'DEMO-%s\n' FAIL` Enter Wait
Sleep 2.5s
Type `make localstack-state-list 2>&1 | head -n 12 || printf 'DEMO-%s\n' FAIL` Enter Wait
Sleep 3s
Hide
Type `clear` Enter Wait
Show

# DEMO-SECTION destroy
Hide
Type `make destroy > "$RUN/destroy.log" 2>&1; echo $? > "$RUN/destroy.rc"` Enter Wait
Show
Type `grep -E 'Destroy complete' "$RUN/destroy.log" || printf 'DEMO-%s\n' FAIL` Enter Wait
Sleep 3s
