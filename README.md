# Reaper Arena

A top-down action survival game built with **LÖVE2D (Lua)**.  
The player fights off relentless reapers in an enclosed arena, collecting coins, managing health, and surviving as long as possible while enemy difficulty dynamically increases.

---

## 🎮 Gameplay Overview

- You control a **melee character** inside an arena.
- **Reapers (enemies)** pursue the player using smart AI.
- Collect **coins** to increase your score — but each coin makes enemies faster.
- **Heart pickups** can restore health when you are injured.
- After reaching a score threshold, a **second reaper** joins the fight.
- The game ends when the player loses all health.

The goal is simple: **survive and achieve the highest score possible.**

---

## ✨ Features

### Core Mechanics
- Smooth player movement with **normalized diagonal movement**
- Melee combat with hit detection
- Enemy combat with cooldowns and damage
- Coin and heart pickup system
- Dynamic difficulty scaling

### AI
- Enemies use **Line-of-Sight detection**
- When blocked, enemies navigate around obstacles using **A\* pathfinding**
- Intelligent switching between direct chase and grid-based navigation

### UI / UX
- Pixel-style graphical user interface
- Health displayed as **heart shapes**
- Centered score & best score display
- **Danger level bar** showing enemy threat
- Pause menu (ESC) with Resume / Main Menu options
- Main menu with difficulty selection and high scores

### Audio & Visuals
- Sprite-sheet based animations
- Sword swing, enemy attack, coin pickup, and heart pickup sounds
- Particle effects for hits, deaths, coins, and hearts
- Pixelated font for menus and in-game UI
- Background image on main menu

### Replayability
- Multiple difficulty levels (Easy / Normal / Hard)
- Session-persistent high scores saved to file
- Increasing challenge over time
- Second enemy spawn for late-game pressure

---

## 🧠 AI & Technical Details

- **A\* Pathfinding** on a tile grid
- Line-of-sight optimization to avoid unnecessary pathfinding
- Wall sliding collision resolution
- Enemy behavior adapts based on environment and player position
- Code is modularized into separate files:
  - `player.lua`
  - `enemy.lua`
  - `coin.lua`
  - `heartpickup.lua`
  - `wall.lua`
  - `animation.lua`
  - `main.lua`

---

## 🕹 Controls

| Action | Key |
|------|-----|
| Move | WASD / Arrow Keys |
| Attack | Space |
| Pause | ESC |
| Resume / Restart | Enter |
| Toggle AI Path Debug | F1 |
| Quit | Menu / Pause Menu |
