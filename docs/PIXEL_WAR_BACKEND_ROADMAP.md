# Pixel War Backend Roadmap
Last updated: 2026-05-15

## Goal

Keep Pixel War as a Solar2D/Lua client while moving online, social, guild, and economy-sensitive state to the server.

The current backend is a Node/Express HTTP API in `server/pixelwar server/server.js`.
Do not assume a Go/PostgreSQL rewrite is the current plan.

## Current Stack

- Client: Solar2D/Lua
- Backend API: Node/Express
- Transport: HTTP/JSON
- Current development storage: JSON-backed server state
- Shared client API modules:
  - `client/utils/api.lua`
  - `client/utils/session.lua`
  - `client/utils/sync.lua`

## Architecture Rules

- Server owns online/economy/social state.
- Client may cache server state locally.
- Client cache is not final truth for server-owned systems.
- Scenes should call helpers/API wrappers instead of raw network calls.
- Server-approved player snapshots should be applied through `utils/sync.lua`.
- Avoid writing guild/economy changes only into local save.

## Active Server-Owned Systems

- Accounts/login/profile selection
- Player profile sync
- Friends
- Messages
- Guild search/profile
- Guild create/join/leave
- Guild crew roles and kicking
- Guild chat
- Guild vault
- Guild land collection
- Guild jail
- Guild loot prepare/report
- Guild auctions
- PvP opponent search
- PvP history/report
- Squad/conquer tax reporting

## Guild Rules

- A player may have one joined guild and one created/led guild.
- Creating a guild must not require leaving a joined guild.
- Joining another guild requires leaving the current joined guild.
- A player may not lead more than one guild.
- Guild membership must reconcile from server guild state.
- Kicked players should lose the guild on next server sync.

## Guild Economy Rules

- Guild vault is server-owned.
- Guild LAND collection deposits directly into the server guild vault.
- LAND rewards do not go into the leader's personal inventory.
- Guild loot success grants server-approved rewards to the challenger.
- Guild loot failure creates a 24-hour jail entry.
- Jailed players cannot loot guilds.
- Jailed players pay 10% arena gold tax to the jail guild.

## Arena/PvP Rules

- The server can provide real player snapshots and bots for arena.
- Arena refresh should show opponents at the selected target level.
- Fight All must fight the 8 visible arena opponents.
- If fewer than 8 real players exist, fill with bots.
- Combat log replay must remain stable.
- Tapping Fight All results replays the full fight from the beginning.

## Current Priorities

1. Keep guild state server-owned.
2. Keep guild vault/land/loot/jail synchronized across profiles.
3. Keep arena refresh and Fight All consistent.
4. Move economy-sensitive actions behind server endpoints.
5. Preserve local save only as cache/offline continuity.

## Future Production Migration

If the game later needs a production-grade backend, revisit:

- PostgreSQL for durable data
- Redis for presence/rate limits/queues
- WebSockets for live chat/presence
- server-side combat resolution for competitive PvP

That migration is not the immediate roadmap. The current priority is stabilizing the working Node server and Solar2D client.

