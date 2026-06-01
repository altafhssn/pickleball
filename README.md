# Pickleball Smash 🏓

The fastest-growing sport, now in your pocket.

A mobile-first, real-time multiplayer pickleball game built with **Godot 4**.

## 🎮 Features

- **Authentic pickleball physics** — Wiffle ball drag, kitchen zone, two-bounce rule, underhand serve
- **Touch controls** — Swipe lob/dink/cross-court, tap volley, double-tap power charge, hold+drag precision
- **Multiple modes** — Quick Match, Practice vs AI, Doubles 2v2
- **Tournaments** — 8-player single-elimination bracket with scaling AI difficulty
- **Daily Challenges** — 3 random skill challenges that reset daily
- **Progression** — 50 player levels, 10 paddle sidegrades, XP/coins/gems economy
- **Shop** — Buy and equip paddles with power/control/spin/reach tradeoffs
- **AI opponents** — 5 difficulty levels (Beginner → Champion) with decision tree AI
- **Game feel** — Camera shake, screen flash, paddle swing animations, celebrate jumps
- **Audio** — SFX for hits, bounces, serves, scoring + ball trail VFX

## 🛠️ Tech Stack

- **Engine:** Godot 4.6.2
- **Scripting:** GDScript
- **Physics:** Full 3D (RigidBody3D) with custom drag model
- **Rendering:** Mobile renderer, 1080×1920 portrait
- **Audio:** Generated OGG Vorbis

## 🚀 Getting Started

```bash
git clone https://github.com/altafhssn/pickleball.git
cd pickleball
godot .
```

Requires [Godot 4.6.2](https://godotengine.org/download/) or later.

## 📁 Project Structure

```
pickleball/
├── project.godot          # Project configuration
├── scenes/
│   ├── Main.tscn          # Game orchestrator
│   ├── Gameplay/          # Court, Ball, Player, HUD, VFX
│   ├── Menus/             # MainMenu, Shop, Tournament, Challenges, Settings
│   └── UI/                # ScreenTransition overlay
├── scripts/               # 22 GDScript files
└── assets/audio/          # 5 OGG SFX files
```

## 📊 Development Status

- ✅ P0 — Foundation
- ✅ P1 — Core Gameplay
- ✅ P2 — Visual & Audio Polish
- ✅ P3 — Progression
- ✅ P4 — Features (Doubles, Tournaments, Challenges)
- ✅ P5 — Game Feel & UI Polish
- ⬜ P6 — Global Launch

---

*Built by [Straw Hat Studio](https://github.com/altafhssn)*
