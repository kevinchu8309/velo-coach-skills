#!/bin/bash
# Velo Coach — intervals.icu Data Sync
# Usage: sync.sh
# Fetches wellness, power curves, activities, and intervals from intervals.icu

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/.env"

DATA_DIR="$PROJECT_DIR/data/synced"
TMP_DIR="$DATA_DIR/.tmp"
BACKUP_DIR="$DATA_DIR/.backup"

# ─── Load env ───
if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: .env not found at $ENV_FILE"
  echo "Copy .env.example to .env and fill in your API credentials."
  exit 1
fi
export $(grep -v '^#' "$ENV_FILE" | grep -v '^\s*$' | xargs)

# ─── Validate required vars ───
for var in INTERVALS_ICU_API_KEY INTERVALS_ICU_ATHLETE_ID; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: Missing $var in .env"
    exit 1
  fi
done

# ─── Setup ───
mkdir -p "$DATA_DIR/laps" "$BACKUP_DIR" "$TMP_DIR"

OLDEST="$(date -v-90d +%Y-%m-%d 2>/dev/null || date -d '90 days ago' +%Y-%m-%d)"
NEWEST="$(date +%Y-%m-%d)"
ICU_AUTH=$(echo -n "API_KEY:${INTERVALS_ICU_API_KEY}" | base64)
ICU_BASE="https://intervals.icu/api/v1/athlete/${INTERVALS_ICU_ATHLETE_ID}"

EXISTING_LAPS="$(find "$DATA_DIR/laps" -name '*.json' 2>/dev/null | wc -l | tr -d ' ')"
LAPS_DAYS=14
if [[ "$EXISTING_LAPS" -eq 0 ]]; then
  LAPS_DAYS=90
  echo "First sync — fetching laps for last ${LAPS_DAYS} days"
fi

echo "=== Velo Coach Sync ==="
echo "Range: $OLDEST to $NEWEST | Laps: last ${LAPS_DAYS} days"
echo ""

# ─── Backup existing data ───
for f in wellness.json activities.json; do
  if [[ -f "$DATA_DIR/$f" ]]; then
    cp "$DATA_DIR/$f" "$BACKUP_DIR/${f%.json}.$(date +%Y%m%d%H%M).json"
  fi
done
# Keep only last 5 backups per type
for prefix in wellness activities; do
  ls -t "$BACKUP_DIR/${prefix}".*.json 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null || true
done

# ═══════════════════════════════════════
# 1. WELLNESS (CTL/ATL/TSB/eFTP)
# ═══════════════════════════════════════
echo "Fetching wellness data..."
WELLNESS_TMP="$TMP_DIR/wellness.json"
if curl -sf \
  -H "Authorization: Basic $ICU_AUTH" \
  "${ICU_BASE}/wellness?oldest=${OLDEST}&newest=${NEWEST}" \
  -o "$WELLNESS_TMP"; then
  COUNT=$(python3 -c "
import json, sys
try:
    data = json.load(open('$WELLNESS_TMP'))
    assert isinstance(data, list) and len(data) > 0
    print(len(data))
except:
    sys.exit(1)
" 2>/dev/null) && {
    mv "$WELLNESS_TMP" "$DATA_DIR/wellness.json"
    echo "   OK: ${COUNT} wellness days"
  } || {
    echo "   WARNING: Wellness data invalid, keeping previous version"
    rm -f "$WELLNESS_TMP"
  }
else
  echo "   WARNING: intervals.icu wellness API failed, keeping previous version"
fi

# ═══════════════════════════════════════
# 2. POWER CURVES
# ═══════════════════════════════════════
echo "Fetching power curves..."
PC_TMP="$TMP_DIR/power-curves-raw.json"
if curl -sf \
  -H "Authorization: Basic $ICU_AUTH" \
  "${ICU_BASE}/power-curves.json?type=Ride&curves=42d,1y" \
  -o "$PC_TMP"; then

  DATA_DIR="$DATA_DIR" TMP_DIR="$TMP_DIR" python3 << 'PCEOF'
import json, os, sys
from datetime import datetime
data_dir, tmp = os.environ["DATA_DIR"], os.environ["TMP_DIR"]
try:
    raw = json.load(open(os.path.join(tmp, "power-curves-raw.json")))
    curves_list = raw.get("list", [])
    assert len(curves_list) > 0
except:
    print("   WARNING: Power curve data invalid"); sys.exit(1)
KEY_DURATIONS = [5, 15, 30, 60, 120, 300, 600, 1200, 2400, 3600]
result = {"synced_at": datetime.now().strftime("%Y-%m-%d %H:%M"), "curves": {}}
for curve in curves_list:
    curve_id = curve.get("id", "unknown")
    secs, watts = curve.get("secs", []), curve.get("watts", [])
    extracted = {}
    for t in KEY_DURATIONS:
        if t in secs:
            idx = secs.index(t)
            val = watts[idx] if idx < len(watts) and watts[idx] is not None else None
            extracted[str(t)] = round(val) if val else None
        else:
            extracted[str(t)] = None
    result["curves"][curve_id] = {"label": curve.get("label", curve_id), "watts": extracted}
with open(os.path.join(data_dir, "power-curves.json"), "w") as f:
    json.dump(result, f, indent=2, ensure_ascii=False)
print(f"   OK: Power curves — {len(result['curves'])} time ranges")
PCEOF
  [[ $? -ne 0 ]] && echo "   WARNING: Power curves parse failed, skipping"
  rm -f "$PC_TMP"
else
  echo "   WARNING: Power curves fetch failed, skipping"
fi

# ═══════════════════════════════════════
# 3. ACTIVITIES
# ═══════════════════════════════════════
echo "Fetching activities..."
ACT_TMP="$TMP_DIR/icu_activities.json"
if curl -sf \
  -H "Authorization: Basic $ICU_AUTH" \
  "${ICU_BASE}/activities?oldest=${OLDEST}&newest=${NEWEST}" \
  -o "$ACT_TMP"; then

  TMP_DIR="$TMP_DIR" DATA_DIR="$DATA_DIR" python3 << 'PYEOF'
import json, os
raw = json.load(open(os.path.join(os.environ["TMP_DIR"], "icu_activities.json")))
data_dir = os.environ["DATA_DIR"]
all_acts = []
for act in raw:
    if act.get("type") not in ("Ride", "VirtualRide"): continue
    kj = round(act["icu_joules"] / 1000, 1) if act.get("icu_joules") else None
    all_acts.append({
        "id": act["id"], "name": act.get("name",""), "type": act["type"],
        "start_date_local": act.get("start_date_local",""),
        "moving_time": act.get("moving_time",0),
        "distance": act.get("icu_distance", act.get("distance",0)),
        "average_watts": act.get("average_watts"),
        "weighted_average_watts": act.get("icu_weighted_avg_watts"),
        "max_watts": act.get("max_watts"),
        "average_heartrate": act.get("average_heartrate"),
        "max_heartrate": act.get("max_heartrate"),
        "average_cadence": act.get("average_cadence"),
        "kilojoules": kj,
        "icu_training_load": act.get("icu_training_load"),
        "icu_ftp": act.get("icu_ftp"),
        "device_watts": act.get("device_watts"),
        "total_elevation_gain": act.get("total_elevation_gain",0),
    })
if all_acts:
    with open(os.path.join(data_dir, "activities.json"), "w") as f:
        json.dump(all_acts, f, indent=2, ensure_ascii=False)
    print(f"   OK: {len(all_acts)} cycling activities")
else:
    print("   WARNING: No cycling activities found")
PYEOF
  rm -f "$ACT_TMP"
else
  echo "   WARNING: Activities fetch failed"
fi

# ═══════════════════════════════════════
# 4. INTERVALS (LAPS)
# ═══════════════════════════════════════
echo "Fetching intervals (last ${LAPS_DAYS} days)..."
RECENT_CUTOFF=$(date -v-${LAPS_DAYS}d +%Y-%m-%d 2>/dev/null || date -d "${LAPS_DAYS} days ago" +%Y-%m-%d)

[[ ! -f "$DATA_DIR/activities.json" ]] && echo "   WARNING: No activities.json, skipping intervals" && {
  echo ""
  echo "=== Sync Complete ==="
  date +"%Y-%m-%d %H:%M" > "$DATA_DIR/.last_sync"
  echo "Synced at: $(cat "$DATA_DIR/.last_sync")"
  exit 0
}

python3 << PYEOF > "$TMP_DIR/intervals_todo.txt"
import json
for a in json.load(open("$DATA_DIR/activities.json")):
    if a["start_date_local"][:10] >= "$RECENT_CUTOFF":
        name = a.get("name","").replace("\t"," ")
        print(f"{a['id']}\t{a['start_date_local'][:10]}\t{name}")
PYEOF

while IFS=$'\t' read -r ACT_ID ACT_DATE ACT_NAME; do
  LAP_FILE="$DATA_DIR/laps/${ACT_ID}.json"
  [[ -f "$LAP_FILE" ]] && echo "   - ${ACT_DATE} (cached)" && continue

  INT_TMP="$TMP_DIR/int_${ACT_ID}.json"
  curl -sf \
    -H "Authorization: Basic $ICU_AUTH" \
    "https://intervals.icu/api/v1/activity/${ACT_ID}/intervals" \
    -o "$INT_TMP" 2>/dev/null || { echo "   WARNING: ${ACT_DATE} — fetch failed"; rm -f "$INT_TMP"; continue; }

  ACT_DATE="$ACT_DATE" ACT_ID="$ACT_ID" ACT_NAME="$ACT_NAME" LAP_FILE="$LAP_FILE" INT_TMP="$INT_TMP" python3 << 'INTEOF'
import json, os, sys
try:
    raw = json.load(open(os.environ["INT_TMP"]))
    intervals = raw.get("icu_intervals", [])
    if not intervals: sys.exit(1)
    condensed, np_parts = [], []
    for i, iv in enumerate(intervals):
        dur = iv.get("moving_time") or iv.get("elapsed_time", 0)
        condensed.append({
            "lap": i+1, "name": iv.get("label") or iv.get("type", f"Interval {i+1}"),
            "type": iv.get("type",""), "duration": dur,
            "watts": iv.get("average_watts"), "np": iv.get("weighted_average_watts"),
            "hr": iv.get("average_heartrate"), "max_hr": iv.get("max_heartrate"),
            "cadence": iv.get("average_cadence"), "distance": round(iv.get("distance",0)),
            "zone": iv.get("zone"), "training_load": iv.get("training_load"),
        })
        if iv.get("weighted_average_watts") and dur > 0:
            np_parts.append((iv["weighted_average_watts"]**4) * dur)
    total_dur = sum((iv.get("moving_time") or iv.get("elapsed_time",0)) for iv in intervals)
    true_np = round((sum(np_parts)/total_dur)**0.25) if total_dur > 0 and np_parts else None
    result = {"activity_id": os.environ["ACT_ID"], "date": os.environ["ACT_DATE"],
              "name": os.environ["ACT_NAME"], "laps": condensed, "true_np": true_np}
    with open(os.environ["LAP_FILE"], "w") as f:
        json.dump(result, f, indent=2, ensure_ascii=False)
except Exception as e:
    print(f"   WARNING: parse error: {e}", file=sys.stderr); sys.exit(1)
INTEOF

  [[ $? -eq 0 ]] && echo "   OK: ${ACT_DATE}" || { echo "   WARNING: ${ACT_DATE} — parse failed"; rm -f "$LAP_FILE"; }
  rm -f "$INT_TMP"; sleep 0.3
done < "$TMP_DIR/intervals_todo.txt"
rm -f "$TMP_DIR/intervals_todo.txt"

# ═══════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════
echo ""
echo "=== Sync Complete ==="
echo "  wellness.json     — $(python3 -c "import json; print(len(json.load(open('$DATA_DIR/wellness.json'))))" 2>/dev/null || echo '?') days"
echo "  power-curves.json — $(python3 -c "import json; print(len(json.load(open('$DATA_DIR/power-curves.json')).get('curves',{})))" 2>/dev/null || echo '?') curves"
echo "  activities.json   — $(python3 -c "import json; print(len(json.load(open('$DATA_DIR/activities.json'))))" 2>/dev/null || echo '?') activities"
echo "  laps/             — $(ls "$DATA_DIR/laps/"*.json 2>/dev/null | wc -l | tr -d ' ') files"
date +"%Y-%m-%d %H:%M" > "$DATA_DIR/.last_sync"
echo "  Synced at: $(cat "$DATA_DIR/.last_sync")"
