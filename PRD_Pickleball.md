# PRD: Pickleball Smash — Mobile Real-Time PvP

> **Version:** 1.1
> **Date:** May 31, 2026
> **Review Status:** ✅ Reviewed by reasoning agent — issues applied
> **Platform:** Android & iOS (Godot 4)
> **Studio:** Straw Hat Studio

---

## 1. Executive Summary

Pickleball Smash is a **mobile-first, real-time multiplayer pickleball game** built in Godot 4. It targets the massive gap in the pickleball gaming market — there are only 3 poor-quality pickleball games on mobile (avg rating ★2.5), while the sport itself has 50M+ players globally and is the fastest-growing sport in America. Meanwhile, Tennis Clash (★4.65, 471K ratings) proves massive demand for mobile racket sports.

**Tagline:** *"The fastest-growing sport, now in your pocket."*

---

## 2. Market Analysis

### Competitive Landscape

| Game | Rating | Reviews | Type | Notes |
|------|--------|---------|------|-------|
| Pickleball Stars | ★3.1 | 23 | 3D Sim | 727MB, loot boxes, only real sim |
| Ultimate PickleBall | ★2.3 | 45 | Casual | Tournament style, 200 opponents |
| PickleBall 3D | ★2.0 | 3 | 3D | New, buggy, claims MP |
| **Tennis Clash** | ★4.65 | 471K | PvP Sports | Gold standard for mobile racket sports |
| **Ping Pong Fury** | ★4.72 | 37K | PvP Sports | Swipe controls, online MP |

### Market Gap

- **Zero high-quality pickleball games** exist on mobile
- Pickleball's unique mechanics (kitchen zone, underhand serve, dinking, doubles) are unrepresented in any game
- No game has cracked **real-time PvP** for pickleball
- The sport's player base is growing 15-20% YoY globally

### Target Audience

- **Primary:** Casual mobile gamers aged 25-55 (aligns with real pickleball demographics)
- **Secondary:** Pickleball enthusiasts who want to play on-the-go
- **Tertiary:** Competitive mobile gamers seeking a new PvP sports title

---

## 3. Game Overview

### Core Concept

Real-time 1v1 and 2v2 pickleball matches with intuitive swipe controls, physics-based ball mechanics, and progression systems. Players compete in ranked matchmaking, tournaments, and casual games.

### USPs (Unique Selling Points)

1. **Authentic pickleball physics** — Kitchen/no-volley zone, two-bounce rule, underhand serves
2. **Real-time PvP** — Matchmake against players worldwide (like Tennis Clash)
3. **Doubles mode** — 2v2 with AI partner or real friend (unique vs Tennis Clash)
4. **Accessible controls** — Swipe to hit, tap to position, drag for spin
5. **Growth system** — Ranked tiers, paddle/gear unlocks, cosmetic customization

---

## 4. Core Gameplay

### Match Mechanics

- **Standard pickleball rules:** Underhand serve, must bounce once on each side (two-bounce rule), no volleys in kitchen zone
- **Scoring:** Rally scoring (every rally scores a point — faster, more casual-friendly). Traditional scoring (only server scores) considered for post-launch update
- **Game length:** First to 11 points, win by 2
- **Match types:** Singles (1v1), Doubles (2v2 with AI partner), Doubles (2v2 co-op with friend)

### Controls

| Input | Action |
|-------|--------|
| Swipe up | Lob shot (deep return) |
| Swipe down | Dink shot (soft, kitchen zone) |
| Swipe left/right | Cross-court shot |
| Tap + drag (aim) | Directional precision shot |
| Quick tap (before ball crosses net) | Volley |
| Hold + release | Power shot (risk/reward — easy to miss) |

### Shot Types

1. **Dink** — Soft shot landing in kitchen, resets the point
2. **Drive** — Powerful groundstroke, pace-heavy
3. **Lob** — High arc over opponent's head
4. **Volley** — Hit before ball bounces (cannot hit from kitchen)
5. **Erne** — Advanced: jump around kitchen to volley (unlockable skill)
6. **ATP (Around The Post)** — Advanced: hit around net post (unlockable skill)

### Court & Visuals

- Third-person 3D perspective (behind and above player, like Tennis Clash/real sports games)
- Bright, colorful courts with customization options
- Ball trail effects for spin visibility
- Character avatars with emotes/celebrations

---

## 5. Game Modes

### Core Modes

1. **Quick Match** — Casual 1v1, no stakes, fast matchmaking
2. **Ranked** — Competitive 1v1 with ELO/MMR system, seasons, rewards
3. **Doubles** — 1v2 with AI partner, or 2v2 with friend (co-op matchmaking)

### Secondary Modes

4. **Tournaments** — 8/16/32 player brackets, running every few hours
5. **Challenges** — Daily and weekly skill challenges (e.g., "Win 5 points via dinks")
6. **Practice** — Solo court vs AI with adjustable difficulty levels. **Works offline** — uses cached AI profiles, no internet required
7. **Replay Mode** — Watch your last 5 matches. Works offline.
8. **Events** — Limited-time themed events (holiday courts, special rules)

---

## 6. Progression & Economy

### Player Progression

| System | Description |
|--------|-------------|
| Player Level | XP earned from matches. Unlocks features, modes, cosmetics |
| Ranked Tier | Bronze → Silver → Gold → Platinum → Diamond → Elite → Champion |
| Paddle Level | Upgrade paddles for stat boosts (power, control, spin, reach) |
| Character Level | Each character levels up, unlocking unique emotes/skins |

### Monetization (Free-to-Play, Fair)

| Item | Type | Notes |
|------|------|-------|
| Paddle Skins | Cosmetic | Visual-only, no stat changes |
| Character Skins | Cosmetic | Outfits, court gear |
| Court Themes | Cosmetic | Different court colors/designs |
| Emotes | Cosmetic | Celebration animations |
| XP Boosters | Consumable | Double XP for limited matches |
| Season Pass | Premium Track | Tiered rewards, exclusive cosmetics |
| Paddle Sidegrades | Earnable | Trade-offs (power vs control, spin vs reach) — never pure stat upgrades. All earnable through gameplay |

**No pay-to-win.** Paddles are **cosmetic-only** or **sidegrades** (trade power for control). No stat can be purchased with real money that gives a competitive advantage. All gameplay-affecting items are earnable through matches. Monetization follows Fortnite/Brawl Stars model: cosmetics, season passes, and convenience items only.

### Currencies

| Currency | Earned By | Used For |
|----------|-----------|----------|
| Coins | Matches, daily rewards | Paddle upgrades, basic cosmetics |
| Gems | Ranked rewards, purchase | Premium cosmetics, season pass, boosters |
| Tokens | Events, tournaments | Limited-time event cosmetics |

---

## 7. Technical Requirements

### Platform
- **Engine:** Godot 4
- **Primary:** iOS & Android
- **Potential:** Web (HTML5 export) for cross-platform

### Online Requirements
### Real-time matchmaking — WebSocket-based server (Nakama or custom Godot server)
- **Server-authoritative model:** Server validates all shot trajectories, timings, and ball physics. Clients send only inputs; server broadcasts verified state.
- Target 20-30Hz update rate with client-side prediction and position interpolation to smooth network jitter
- **Reconnection system:** 30-second reconnection window — AI takes over temporarily if player drops. Prevents frustration from mobile network switches
- **Lobby system** — Friend invites, party up before matches
- **Leaderboard** — Global + friends leaderboards

### Performance Targets
- **iOS:** iPhone X and above, 60fps
- **Android:** 4GB RAM and above, 60fps
- **Install size:** < 150MB (significantly smaller than Pickleball Stars' 727MB)
- **Battery efficient** — matches under 15 minutes

---

## 8. Milestones & Timeline

> ⚠️ **Timeline estimate:** For a small team of 2-3 developers. Solo dev should double these estimates.

| Phase | Scope | Duration |
|-------|-------|----------|
| **P0 — Foundation** | Project setup, 2D physics engine, ball drag/aerodynamics, basic court rendering, touch input system, tutorial scene | 3-4 weeks |
| **P1 — Core Gameplay** | Single-player vs AI, full court, all swipe controls, shot types (dink/drive/lob/volley), pickleball rules engine, gesture guide | 6-8 weeks |
| **P2 — Multiplayer** | Server setup (Nakama), real-time PvP matchmaking, client-side prediction, position interpolation, reconnection system, basic ranking | 6-8 weeks |
| **P3 — Progression** | Player levels, paddle sidegrades, currencies (coins/gems), shop, ranked tiers, season pass | 4-5 weeks |
| **P4 — Features** | Doubles mode (AI partner), tournaments, daily/weekly challenges, events | 5-6 weeks |
| **P5 — Polish & Soft Launch** | Animations, VFX, UI polish, audio, optimization, iOS/Android build, soft launch in 1-2 markets | 4-6 weeks |
| **P6 — Global Launch** | Marketing materials, app store submission, localization (EN), live ops setup, server scaling | 3-4 weeks |

**Estimated: 31-41 weeks (8-10 months)** for a team of 2-3.

**Scope cuts if timeline is critical (v1.0 only):**
- Drop Doubles mode → save 5-6 weeks (move to v1.1)
- Drop Tournaments → save 3-4 weeks (move to v1.2)
- Drop Replay/Spectate → save 2-3 weeks (move to v1.3)
- **Minimum viable v1.0:** 1v1 Quick Match + Ranked + Practice + Shop = ~22-26 weeks

---

## 9. Success Metrics

| Metric | Target (6 months post-launch) |
|--------|-------------------------------|
| Downloads | 500K+ |
| DAU | 25K+ |
| D1 Retention | 40%+ |
| D7 Retention | 20%+ |
| D30 Retention | 8%+ |
| Avg Session Length | 8-12 min |
| Rating | 4.5+ |
| Revenue | TBD based on UA spend |

---

## 10. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Real-time PvP is complex to implement | Start with AI opponent in P1, proven P2P fallback for private lobbies |
| Godot's multiplayer ecosystem less mature than Unity | Use Nakama or dedicated WebSocket server; Godot 4's ENet/MultiplayerAPI is adequate for authoritative server model |
| Small team for 2v2 real-time sync | Phase 4 after 1v1 is stable; simplify with AI partner controlling one side |
| Pickleball niche may be too small in some regions | Localized marketing, target US/UK/Canada first |
| Server cost for authoritative physics calculations | Use lightweight server (single binary) with state validation only; actual physics runs client-side with server verification |
