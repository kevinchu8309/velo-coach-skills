# velo-coach-skills 🚴

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Claude Code](https://img.shields.io/badge/Claude_Code-Skills-orange)](https://docs.anthropic.com/en/docs/claude-code)
[![intervals.icu](https://img.shields.io/badge/intervals.icu-Supported-green)](https://intervals.icu)

AI-powered cycling coach skills for [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

Turn Claude into your personal cycling coach. It reads your power data from [intervals.icu](https://intervals.icu), applies training science, and delivers structured coaching — workout prescriptions, ride reviews, recovery protocols, race strategy, and more.

## What it does

Seven coaching skills, each triggered by natural conversation:

| Skill | Trigger | What it does |
|-------|---------|-------------|
| `/sync` | "sync my data" | Pull latest data from intervals.icu |
| `/status` | "how am I doing" | Daily check-in: PMC/TSB, safety alerts, goal progress, power profile |
| `/plan` | "what should I ride" | Prescribe workouts with precise power targets, cadence, and bail-out rules |
| `/ride-review` | "how was that ride" | Post-ride analysis: compliance scoring, cardiac drift, efficiency factor |
| `/recovery` | "recovery advice" | Personalized recovery protocol with macro calculations and supplement guidance |
| `/weekly-review` | "how was this week" | Weekly summary: TSS vs targets, zone distribution, monotony/strain |
| `/race` | "race prep" | Race analysis (pacing, surges, tactics) or pre-race preparation protocol |

### Built-in training science

- **Coggan 7-zone power model** with automatic zone calculation from FTP
- **Compliance scoring** algorithm (power accuracy 40%, duration 25%, consistency 20%, HR 15%)
- **Cardiac drift** and **Efficiency Factor** tracking for aerobic fitness assessment
- **Training monotony and strain** calculations (Banister model)
- **Periodized workout library** with 25+ workouts across 5 training phases
- **Evidence-ranked supplement guide** and **precise macro calculations**
- **Plateau detection** with stimulus variation strategies
- **Return-to-training protocols** for illness and injury
- **Taper science** for race preparation
- **Safety alerts**: overtraining red flags, immune window warnings, load management

## Quick Start

### 1. Clone and configure

```bash
git clone https://github.com/kevinchu8309/velo-coach-skills.git
cd velo-coach-skills

# Set up your intervals.icu API credentials
cp .env.example .env
# Edit .env with your API key and athlete ID

# Set up your athlete profile
cp data/athlete.json.example data/athlete.json
# Edit data/athlete.json with your FTP, weight, zones, etc.

# (Optional) Set up a training plan
cp data/training-plan.json.example data/training-plan.json
# Edit data/training-plan.json to match your goals
```

### 2. Sync your data

```bash
bash scripts/sync.sh
```

### 3. Start coaching

```bash
claude
```

Then just talk to your coach:
- "How am I doing?"
- "What should I ride today?"
- "How was yesterday's ride?"
- "I'm tired, slept badly"
- "Recovery advice after today's session"

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI installed
- An [intervals.icu](https://intervals.icu) account (free) with your cycling data
- Python 3.x (for the sync script)
- `curl` and `bash`

### Getting your intervals.icu API key

1. Go to [intervals.icu](https://intervals.icu) and log in
2. Navigate to Settings (gear icon) > Developer
3. Create a new API key
4. Your Athlete ID is shown on the same page (starts with `i`)

## Example Output

### `/status` — Daily Check-in
```
🚴 Fitness Check — 2026-03-21

📊 PMC Status
CTL: 63 | ATL: 73 | TSB: -10
Trend: CTL ↑3 this week | Ramp rate: +1.8/wk

⚡ Power Profile (42-day bests)
5s: 520W (7.4 W/kg) | 1min: 350W (5.0) | 5min: 280W (4.0) | 20min: 240W (3.4)

🎯 Goal Progress
FTP: 200W → 250W target (80% there)
W/kg: 2.86 → 3.57 target

🟡 Alert: TSB -10 — moderate fatigue accumulation. Consider easy day if legs feel heavy.
```

### `/ride-review` — Post-Ride Analysis
```
🚴 Ride Review: SST 2x20min — 2026-03-21

📊 Overview
Duration: 1:05 | NP: 192W (2.74 W/kg) | IF: 0.96 | TSS: 85

Compliance: 8.2 / 10
├── ⚡ Power accuracy:  90% ██████████████████░░ (0.90)
├── ⏱️ Duration:       100% ████████████████████ (1.00)
├── 📊 Consistency:     85% █████████████████░░░ (0.85)
└── ❤️ HR response:     80% ████████████████░░░░ (0.80)

✅ Strong: Held target watts through both intervals
⚡ Improve: HR drifted 8% — consider more Z2 base work
🔮 Next: Easy spin tomorrow, then threshold intervals Thursday
```

## Project Structure

```
velo-coach-skills/
├── CLAUDE.md                          # System instructions for Claude
├── .claude/commands/                  # Coaching skills
│   ├── status.md                      # Daily check-in
│   ├── plan.md                        # Workout prescription
│   ├── ride-review.md                 # Post-ride analysis
│   ├── recovery.md                    # Recovery & nutrition
│   ├── weekly-review.md               # Weekly summary
│   ├── race.md                        # Race analysis & prep
│   └── sync.md                        # Data sync
├── data/
│   ├── athlete.json                   # Your profile (FTP, weight, zones)
│   ├── training-plan.json             # Periodization plan (optional)
│   ├── synced/                        # Data from intervals.icu
│   │   ├── wellness.json              # Daily CTL/ATL/TSB
│   │   ├── activities.json            # Ride summaries
│   │   ├── power-curves.json          # Power bests (42d + 1y)
│   │   └── laps/                      # Per-ride interval data
│   └── logs/                          # Coaching outputs
│       ├── prescriptions.json         # Workout prescriptions
│       ├── compliance.json            # Ride compliance scores
│       ├── rpe.json                   # Subjective fatigue ratings
│       └── coaching-notes.json        # Plan adjustment history
├── scripts/
│   └── sync.sh                        # intervals.icu data sync
├── .env.example                       # API credentials template
├── LICENSE                            # MIT
└── README.md
```

## Data Flow

```
intervals.icu ──sync.sh──> synced/wellness.json
                           synced/activities.json
                           synced/power-curves.json
                           synced/laps/*.json
                                │
         ┌──────────────────────┤
         ▼                      ▼
    /status              /plan ──> logs/prescriptions.json
    /weekly-review            │
         ▲                    ▼
         │            (athlete rides)
         │                    │
         │                    ▼
    /recovery        /ride-review ──> logs/compliance.json
```

## Customization

### Athlete profile (`data/athlete.json`)

Set your current FTP, weight, max HR, and target goals. All power zones are calculated automatically from FTP using the Coggan 7-zone model.

### Training plan (`data/training-plan.json`)

Optional but recommended. Define your periodization phases with:
- Weekly TSS targets
- Key workouts per phase
- FTP progression goals
- Deload schedule (every 4th week by default)

The example template provides a 16-week plan with 4 phases. Customize the duration, targets, and workouts to match your goals.

### Power zones

Default zones follow the Coggan model. To customize, edit the `zones` object in `athlete.json`. Each zone is defined as `[min_fraction, max_fraction]` of FTP.

## Contributing

Contributions are welcome! Some ideas:

- Additional workout types in the phase libraries
- Support for running/triathlon training
- Integration with other platforms (TrainingPeaks, Garmin Connect)
- Localization (the system currently outputs in English)
- Improved power distribution estimation from interval data

## License

MIT License. See [LICENSE](LICENSE) for details.
