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
Type `record_rc() { echo "$?" > "$RUN/$1.rc"; }` Enter Wait
Type `set -o pipefail; env | grep -c '^RUN=' > "$RUN/env.ok"; clear` Enter Wait
Type `clear` Enter Wait
Show

# DEMO-SECTION status
Hide
Type `make localstack-status > "$RUN/status.log" 2>&1; record_rc status` Enter Wait
Type `clear` Enter Wait
Show
Type `grep -E 'localstack|Service|\b(ec2|ecs|elbv2|s3|iam|logs|secretsmanager|sns|servicediscovery)\b' "$RUN/status.log" 2>/dev/null` Enter Wait
Sleep 2.5s

# DEMO-SECTION plan
Hide
Type `make plan > "$RUN/plan.log" 2>&1; record_rc plan` Enter Wait
Type `clear` Enter Wait
Show
Type `grep -E '^Plan:' "$RUN/plan.log"` Enter Wait
Sleep 2.5s

# DEMO-SECTION conftest
Hide
Type `make conftest > "$RUN/conftest.log" 2>&1; record_rc conftest` Enter Wait
Type `clear` Enter Wait
Show
Type `tail -n 3 <"$RUN/conftest.log"` Enter Wait
Sleep 2.5s

# DEMO-SECTION apply
Hide
Type `make apply > "$RUN/apply.log" 2>&1; record_rc apply` Enter Wait
Type `clear` Enter Wait
Show
Type `grep -E 'Apply complete' "$RUN/apply.log"` Enter Wait
Sleep 2.5s

# DEMO-SECTION statelist
Hide
Type `make localstack-state-list > "$RUN/statelist.log" 2>&1; record_rc statelist` Enter Wait
Type `clear` Enter Wait
Show
Type `sed -n '1,12p' "$RUN/statelist.log"` Enter Wait
Sleep 3s

# DEMO-SECTION destroy
Hide
Type `make destroy > "$RUN/destroy.log" 2>&1; record_rc destroy` Enter Wait
Type `clear` Enter Wait
Show
Type `grep -E 'Destroy complete' "$RUN/destroy.log"` Enter Wait
Sleep 3s
