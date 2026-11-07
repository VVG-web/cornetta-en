#!/bin/bash
# QA release gate. Run after ./scripts/check.sh and after every manual TS in docs/QA-TEST-PLAN.md.
#   QA_MANUAL_SIGNOFF=all ./scripts/qa-release.sh
#   QA_MANUAL_SIGNOFF="TS-01 TS-03" ./scripts/qa-release.sh
set -euo pipefail
cd "$(dirname "$0")/.."

PLAN="docs/QA-TEST-PLAN.md"
[ -s "$PLAN" ] || { echo "Missing $PLAN" >&2; exit 1; }

echo "== QA automated checks =="
python3 scripts/localization.py --check
python3 -m unittest discover -s scripts/tests
./scripts/test.sh
(cd windows && dotnet test Cornetta.Windows.sln -c Release --no-restore)
git diff --check

echo "== QA plan coverage =="
python3 - "$PLAN" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
ts = sorted(set(re.findall(r"\bTS-\d{2}\b", text)))
tc = sorted(set(re.findall(r"\bTC-\d{2}\b", text)))
if not ts or not tc:
    raise SystemExit("The QA plan has no TC/TS identifiers")
print(f"{len(tc)} test cases, {len(ts)} manual scenarios")
print(" ".join(ts))
PY

echo "== Manual sign-off =="
SIGNOFF="${QA_MANUAL_SIGNOFF:-}"
if [ -z "$SIGNOFF" ]; then
  cat >&2 <<'MSG'
Set QA_MANUAL_SIGNOFF only after executing every TS in docs/QA-TEST-PLAN.md.
Use QA_MANUAL_SIGNOFF=all, or list the completed IDs, for example:
  QA_MANUAL_SIGNOFF="TS-01 TS-02 TS-03" ./scripts/qa-release.sh
MSG
  exit 2
fi
if [ "$SIGNOFF" != "all" ]; then
  REQUIRED=$(python3 - "$PLAN" <<'PY'
import re
import sys
from pathlib import Path
print(" ".join(sorted(set(re.findall(r"\bTS-\d{2}\b", Path(sys.argv[1]).read_text(encoding="utf-8"))))))
PY
)
  for id in $REQUIRED; do
    case " $SIGNOFF " in
      *" $id "*) ;;
      *) echo "Missing manual sign-off: $id" >&2; exit 2 ;;
    esac
  done
fi

echo "== Release metadata =="
if [ -n "${RELEASE_VERSION:-}" ]; then
  python3 - "$RELEASE_VERSION" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

version = sys.argv[1]
feed = json.loads(Path("site/update/feed.json").read_text(encoding="utf-8"))
if feed["version"] != version:
    raise SystemExit(f"feed version {feed['version']} != release {version}")
expected = f"https://github.com/VVG-web/cornetta-en/releases/tag/v{version}"
if feed["release_url"] != expected:
    raise SystemExit(f"release URL is {feed['release_url']}, expected {expected}")
for key in ("mac", "windows"):
    asset = Path("dist") / feed[key]["filename"]
    if not asset.exists():
        print(f"warning: {asset} is not present locally; hash cannot be checked")
        continue
    actual = hashlib.sha256(asset.read_bytes()).hexdigest()
    if actual != feed[key]["sha256"]:
        raise SystemExit(f"{asset}: {actual} != {feed[key]['sha256']}")
    print(f"{asset.name}: {actual}")
PY
fi

echo "QA TC and TS passed for ${RELEASE_VERSION:-the current tree}."