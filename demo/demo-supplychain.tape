# Reproducible offline supply-chain demo. Rendered by demo/record.sh; do not run directly.
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

# DEMO-SECTION canon-timestamp
Hide
Type `canon_rc=0; scripts/sbom-canon.sh < tests/fixtures/sbom/base.spdx.json > "$RUN/base.canon" || canon_rc=$?; scripts/sbom-canon.sh < tests/fixtures/sbom/timestamp-only-difference.spdx.json > "$RUN/timestamp.canon" || canon_rc=$?; diff_rc=0; diff -q "$RUN/base.canon" "$RUN/timestamp.canon" > /dev/null || diff_rc=$?; echo "identical=$diff_rc" > "$RUN/canon-timestamp.log"; test "$canon_rc" -eq 0 && test "$diff_rc" -eq 0; record_rc canon-timestamp` Enter Wait
Type `clear` Enter Wait
Show
Type `cat "$RUN/canon-timestamp.log"` Enter Wait
Sleep 2.5s

# DEMO-SECTION canon-checksum
Hide
Type `canon_rc=0; scripts/sbom-canon.sh < tests/fixtures/sbom/same-inventory-different-checksum.spdx.json > "$RUN/checksum.canon" || canon_rc=$?; diff_rc=0; diff -q "$RUN/base.canon" "$RUN/checksum.canon" > /dev/null || diff_rc=$?; echo "identical=$diff_rc" > "$RUN/canon-checksum.log"; test "$canon_rc" -eq 0 && test "$diff_rc" -eq 1; record_rc canon-checksum` Enter Wait
Type `clear` Enter Wait
Show
Type `cat "$RUN/canon-checksum.log"` Enter Wait
Sleep 2.5s

# DEMO-SECTION canon-sha
Hide
Type `sha_rc=0; base_sha=$(shasum -a 256 "$RUN/base.canon" | awk '{print $1}') || sha_rc=$?; timestamp_sha=$(shasum -a 256 "$RUN/timestamp.canon" | awk '{print $1}') || sha_rc=$?; printf 'base sha256=%s\ntimestamp sha256=%s\n' "$base_sha" "$timestamp_sha" > "$RUN/canon-sha.log"; test "$sha_rc" -eq 0 && test "${#base_sha}" -eq 64 && test "$base_sha" = "$timestamp_sha"; record_rc canon-sha` Enter Wait
Type `clear` Enter Wait
Show
Type `cat "$RUN/canon-sha.log"` Enter Wait
Sleep 2.5s

# DEMO-SECTION contracts
Hide
Type `bash tests/sbom-canon.sh > "$RUN/contracts.log" 2>&1; record_rc contracts` Enter Wait
Type `clear` Enter Wait
Show
Type `tail -n 3 "$RUN/contracts.log"` Enter Wait
Sleep 3s
