require("dotenv").config({ quiet: true });

const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const express = require("express");
const { Pool } = require("pg");

const app = express();
const port = process.env.PORT || 3000;
const host = process.env.HOST || "0.0.0.0";
const dataPath = path.join(__dirname, "pixelwar-data.json");
const useDatabaseState = Boolean(process.env.DATABASE_URL);

app.use(express.json({ limit: "2mb" }));

const poolConfig = process.env.DATABASE_URL
  ? { connectionString: process.env.DATABASE_URL }
  : {
      user: process.env.DB_USER,
      host: process.env.DB_HOST,
      database: process.env.DB_NAME,
      password: process.env.DB_PASSWORD,
      port: Number(process.env.DB_PORT) || 5432,
    };

const pool = new Pool(poolConfig);
let saveQueue = Promise.resolve();

function slug(value) {
  return String(value || "")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "")
    .slice(0, 40);
}

function nowLabel() {
  return "NOW";
}

function timestampLabel(date = new Date()) {
  return new Intl.DateTimeFormat("en-US", {
    month: "2-digit",
    day: "2-digit",
    year: "numeric",
    hour: "numeric",
    minute: "2-digit",
  }).format(date);
}

function makeToken(accountId) {
  return `pw_${accountId}_${Math.random().toString(36).slice(2)}${Date.now().toString(36)}`;
}

function normalizeHandle(value) {
  return String(value || "").trim().toLowerCase();
}

function hashPassword(password, salt = crypto.randomBytes(16).toString("hex")) {
  const hash = crypto.scryptSync(String(password || ""), salt, 64).toString("hex");
  return { hash, salt };
}

function verifyPassword(account, password) {
  password = String(password || "");
  if (!account) return false;

  if (account.passwordHash && account.passwordSalt) {
    const candidate = crypto.scryptSync(password, account.passwordSalt, 64);
    const stored = Buffer.from(account.passwordHash, "hex");
    return stored.length === candidate.length && crypto.timingSafeEqual(stored, candidate);
  }

  // One-time migration path for old development accounts that stored plaintext.
  if (account.password && account.password === password) {
    const record = hashPassword(password);
    account.passwordHash = record.hash;
    account.passwordSalt = record.salt;
    account.passwordMigratedAt = new Date().toISOString();
    delete account.password;
    return true;
  }

  return false;
}

function setAccountPassword(account, password) {
  const record = hashPassword(password);
  account.passwordHash = record.hash;
  account.passwordSalt = record.salt;
  delete account.password;
}

function clampProfileSlot(value) {
  const slot = Number(value) || 1;
  return Math.max(1, Math.min(5, Math.floor(slot)));
}

function maxBaseHpForLevel(level) {
  let hp = 100;
  const safeLevel = Math.max(1, Math.floor(Number(level) || 1));
  for (let currentLevel = 2; currentLevel <= safeLevel; currentLevel += 1) {
    const totalPoints = currentLevel <= 10 ? 20 : 30;
    hp += Math.floor(totalPoints * 0.45);
  }
  return hp;
}

function repairInflatedHp(player) {
  if (!player) return false;
  const maxHp = maxBaseHpForLevel(player.level);
  const currentHp = Number(player.hp);
  if (Number.isFinite(currentHp) && currentHp > maxHp * 2) {
    player.hp = maxHp;
    if (player.snapshot && Number(player.snapshot.hp) > maxHp * 2) {
      player.snapshot.hp = maxHp;
    }
    return true;
  }
  return false;
}

const XP_TABLE = {
  1: 30, 2: 40, 3: 50, 4: 60, 5: 70,
  6: 80, 7: 90, 8: 100, 9: 120,
  10: 150, 11: 180, 12: 220, 13: 270, 14: 330,
  15: 400, 16: 480, 17: 560, 18: 650, 19: 750,
  20: 900, 21: 1100, 22: 1300, 23: 1500, 24: 1700,
  25: 1800, 26: 1900, 27: 2000, 28: 2100, 29: 2200,
  30: 2500, 31: 3000, 32: 3500, 33: 4000, 34: 4500,
  35: 5000, 36: 5500, 37: 6000, 38: 6500, 39: 7000,
  40: 8000, 41: 9000, 42: 10000, 43: 11000, 44: 12000,
  45: 13000, 46: 14000, 47: 15000, 48: 16000, 49: 17000,
  50: 18000, 51: 20000, 52: 22000, 53: 24000, 54: 26000,
};

function xpToNextLevel(level) {
  const safeLevel = Math.max(1, Math.floor(Number(level) || 1));
  if (XP_TABLE[safeLevel]) return XP_TABLE[safeLevel];
  return 26000 + (safeLevel - 54) * 2000;
}

function totalAccumulatedXp(level, currentXp) {
  const safeLevel = Math.max(1, Math.floor(Number(level) || 1));
  let total = Math.max(0, Math.floor(Number(currentXp) || 0));
  for (let currentLevel = 1; currentLevel < safeLevel; currentLevel += 1) {
    total += xpToNextLevel(currentLevel);
  }
  return total;
}

function defaultState() {
  return {
    accounts: {},
    tokens: {},
    players: {},
    friends: {},
    guilds: {},
    guildChats: {},
    threads: {},
    walls: {},
    pvpHistory: {},
    notifications: {},
    tournaments: {},
    auditLogs: [],
    nextProfileNumber: 1,
  };
}

let state = defaultState();

function mergeState(savedState) {
  return { ...defaultState(), ...(savedState || {}) };
}

function loadStateFromFile() {
  try {
    if (fs.existsSync(dataPath)) {
      return mergeState(JSON.parse(fs.readFileSync(dataPath, "utf8")));
    }
  } catch (error) {
    console.error("Failed to load data file:", error);
  }

  const empty = defaultState();
  fs.writeFileSync(dataPath, JSON.stringify(empty, null, 2));
  return empty;
}

async function ensureStateTable() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS app_state (
      key TEXT PRIMARY KEY,
      data JSONB NOT NULL,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);
}

async function loadStateFromDatabase() {
  await ensureStateTable();
  const result = await pool.query("SELECT data FROM app_state WHERE key = $1", ["main"]);
  if (result.rows[0] && result.rows[0].data) {
    return mergeState(result.rows[0].data);
  }

  const seededState = fs.existsSync(dataPath) ? loadStateFromFile() : defaultState();
  await saveStateToDatabase(seededState);
  return seededState;
}

async function loadState() {
  if (useDatabaseState) {
    return loadStateFromDatabase();
  }
  return loadStateFromFile();
}

async function saveStateToDatabase(nextState) {
  await ensureStateTable();
  await pool.query(
    `
      INSERT INTO app_state (key, data, updated_at)
      VALUES ($1, $2, NOW())
      ON CONFLICT (key)
      DO UPDATE SET data = EXCLUDED.data, updated_at = NOW()
    `,
    ["main", nextState]
  );
}

function saveState(nextState = state) {
  const stateSnapshot = snapshotValue(nextState);
  if (!useDatabaseState) {
    fs.writeFileSync(dataPath, JSON.stringify(stateSnapshot, null, 2));
    return;
  }

  saveQueue = saveQueue
    .then(() => saveStateToDatabase(stateSnapshot))
    .catch((error) => {
      console.error("Failed to save state to database:", error);
    });
}

async function initializeState() {
  state = await loadState();
  let needsSave = false;
  if (Object.values(state.players || {}).some(repairInflatedHp)) {
    needsSave = true;
  }
  if (Object.values(state.accounts || {}).some((account) => {
    if (!account || !account.password || account.passwordHash) return false;
    setAccountPassword(account, account.password);
    account.passwordMigratedAt = new Date().toISOString();
    return true;
  })) {
    needsSave = true;
  }
  if (needsSave) saveState();
}

function snapshotValue(value) {
  if (value === undefined) return null;
  try {
    return JSON.parse(JSON.stringify(value));
  } catch {
    return value;
  }
}

function addAuditLog({ player, playerId, action, before, after, reason, source, meta } = {}) {
  state.auditLogs = Array.isArray(state.auditLogs) ? state.auditLogs : [];
  const actor = player || (playerId && state.players[playerId]) || null;
  const entry = {
    id: `audit_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 8)}`,
    timestamp: new Date().toISOString(),
    playerId: playerId || (actor && actor.playerId) || null,
    playerName: actor && actor.displayName || null,
    action: action || "unknown",
    before: snapshotValue(before),
    after: snapshotValue(after),
    reason: reason || "",
    source: source || "server",
    meta: snapshotValue(meta || {}),
  };
  state.auditLogs.unshift(entry);
  state.auditLogs = state.auditLogs.slice(0, 500);
  return entry;
}

function pushNotification(playerId, notification) {
  if (!playerId) return null;
  state.notifications = state.notifications || {};
  const entry = {
    id: `notif_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 8)}`,
    createdAt: new Date().toISOString(),
    timeLabel: nowLabel(),
    read: false,
    ...notification,
  };
  state.notifications[playerId] = state.notifications[playerId] || [];
  const duplicate = state.notifications[playerId].find((prior) =>
    prior &&
    prior.type === entry.type &&
    prior.text === entry.text &&
    prior.fromPlayerId === entry.fromPlayerId &&
    (Date.now() - Date.parse(prior.createdAt || 0)) < 60 * 1000
  );
  if (duplicate) return duplicate;
  state.notifications[playerId].unshift(entry);
  state.notifications[playerId] = state.notifications[playerId].slice(0, 50);
  return entry;
}

function notificationPlayerName(player) {
  return player && (player.displayName || player.name) || "Player";
}

function ensureTournamentState(player) {
  player.tournaments = player.tournaments || {};
  player.tournaments.single = player.tournaments.single || { joined: false, joinedAt: null };
  player.tournaments.crew = player.tournaments.crew || { joined: false, joinedAt: null };
  return player.tournaments;
}

function tournamentCounts() {
  const counts = { single: 0, crew: 0 };
  for (const player of Object.values(state.players || {})) {
    ensureTournamentState(player);
    if (player.tournaments.single.joined) counts.single += 1;
    if (player.tournaments.crew.joined) counts.crew += 1;
  }
  return counts;
}

function ensureSquad(player) {
  player.squad = player.squad || {};
  player.squad.conquered = Array.isArray(player.squad.conquered) ? player.squad.conquered : [];
  return player.squad;
}

function mergeSquad(existingSquad, incomingSquad) {
  const merged = {
    ...(incomingSquad || {}),
    conquered: Array.isArray(incomingSquad && incomingSquad.conquered) ? incomingSquad.conquered : [],
  };
  const existing = Array.isArray(existingSquad && existingSquad.conquered) ? existingSquad.conquered : [];
  const existingByKey = new Map(existing.map((member) => [memberKey(member), member]));
  merged.conquered = merged.conquered.map((member) => {
    const prior = existingByKey.get(memberKey(member));
    if (!prior) return member;
    return {
      ...member,
      contributionGold: Math.max(Number(member.contributionGold) || 0, Number(prior.contributionGold) || 0),
      lastBotGoldAt: Math.max(Number(member.lastBotGoldAt) || 0, Number(prior.lastBotGoldAt) || 0) || member.lastBotGoldAt,
    };
  });
  return merged;
}

function memberKey(member) {
  return String(member.targetPlayerId || member.playerId || member.name || "").trim();
}

function clampTaxRate(rate) {
  return Math.max(0, Math.min(0.20, Number(rate) || 0));
}

function findSquadMember(player, payload) {
  const squad = ensureSquad(player);
  const wanted = String(payload.memberId || payload.playerId || payload.targetPlayerId || payload.name || "").trim();
  return squad.conquered.find((member) => memberKey(member) === wanted || member.name === wanted);
}

function collectBotSquadGold(player) {
  const squad = ensureSquad(player);
  const now = Date.now();
  let gained = 0;
  for (const member of squad.conquered) {
    if (!member.bot) continue;
    const last = Number(member.lastBotGoldAt) || now;
    const ticks = Math.floor((now - last) / (12 * 60 * 60 * 1000));
    if (ticks <= 0) {
      member.lastBotGoldAt = last;
      continue;
    }
    const amount = ticks * 10;
    member.lastBotGoldAt = last + ticks * 12 * 60 * 60 * 1000;
    member.contributionGold = (Number(member.contributionGold) || 0) + amount;
    gained += amount;
  }
  if (gained > 0) player.gold = (Number(player.gold) || 0) + gained;
  return gained;
}

function normalizeProfileCounter() {
  const numericNames = Object.values(state.players || {})
    .map((player) => Number(player && player.displayName))
    .filter((value) => Number.isInteger(value) && value > 0);
  const nextFromPlayers = numericNames.length ? Math.max(...numericNames) + 1 : 1;
  state.nextProfileNumber = Math.max(Number(state.nextProfileNumber) || 1, nextFromPlayers);
}

function nextProfileDisplayName() {
  normalizeProfileCounter();
  const name = String(state.nextProfileNumber);
  state.nextProfileNumber += 1;
  return name;
}

normalizeProfileCounter();

function seedPlayer(seed, playerId, displayName, level, currentScene, guildId, guildName, role) {
  const accountId = `seed_${playerId}`;
  seed.accounts[accountId] = {
    accountId,
    accountKey: accountId,
    displayName,
    playerId,
    activePlayerId: playerId,
    playerIds: [playerId],
    profileSlots: { "1": playerId },
    createdAt: new Date().toISOString(),
  };
  seed.players[playerId] = {
    playerId,
    accountId,
    displayName,
    level,
    status: "online",
    currentScene,
    guilds: guildId ? [{ guildId, name: guildName, role }] : [],
    weapons: [],
    pets: [],
    bio: "Server seed player.",
  };
  seed.friends[playerId] = [];
}

function normalizeAccount(account) {
  if (!account) return null;
  account.playerIds = Array.isArray(account.playerIds) ? account.playerIds : [];
  account.profileSlots = account.profileSlots || {};

  if (account.playerId && !account.playerIds.includes(account.playerId)) {
    account.playerIds.push(account.playerId);
  }

  if (account.playerId && !Object.values(account.profileSlots).includes(account.playerId)) {
    account.profileSlots["1"] = account.playerId;
  }

  account.activePlayerId = account.activePlayerId || account.playerId || account.playerIds[0];
  account.playerId = account.activePlayerId;
  return account;
}

function findAccountByHandle(handle) {
  const normalized = normalizeHandle(handle);
  if (!normalized) return null;
  for (const account of Object.values(state.accounts || {})) {
    if (!account) continue;
    const accountUserId = normalizeHandle(account.userId || account.accountKey || "");
    if (accountUserId === normalized) return normalizeAccount(account);
  }
  return null;
}

function isDisplayNameTaken(displayName, excludePlayerId) {
  const normalized = normalizeHandle(displayName);
  if (!normalized) return false;
  for (const player of Object.values(state.players || {})) {
    if (!player || player.playerId === excludePlayerId) continue;
    if (normalizeHandle(player.displayName) === normalized) {
      return true;
    }
  }
  return false;
}

function createPlayer(account, playerId, displayName, profileSlot) {
  const player = {
    playerId,
    accountId: account.accountId,
    profileSlot,
    displayName,
    level: 1,
    status: "online",
    currentScene: "Home",
    guilds: [],
    weapons: [],
    pets: [],
    bio: "Pixel War player.",
  };
  state.players[playerId] = player;
  state.friends[playerId] = [];
  return player;
}

function seedGuild(seed, guildId, name, leaderPlayerId) {
  const leader = seed.players[leaderPlayerId];
  seed.guilds[guildId] = {
    guildId,
    name,
    leaderPlayerId,
    maxMembers: 20,
    isPublic: true,
    level: 1,
    members: leaderPlayerId ? [leaderPlayerId] : [],
    createdAt: new Date().toISOString(),
  };
  if (leader && !leader.guilds.some((guild) => guild.guildId === guildId)) {
    leader.guilds.push({ guildId, name, role: "Leader" });
  }
}

function getAuthedPlayer(req) {
  const header = req.headers.authorization || "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : null;
  const tokenContext = token && state.tokens[token];
  const accountId = typeof tokenContext === "string" ? tokenContext : tokenContext && tokenContext.accountId;
  const tokenPlayerId = tokenContext && typeof tokenContext === "object" ? tokenContext.playerId : null;
  if (!accountId) return null;
  const account = normalizeAccount(state.accounts[accountId]);
  if (!account) return null;
  return state.players[tokenPlayerId || account.activePlayerId || account.playerId] || null;
}

function requirePlayer(req, res, next) {
  const player = getAuthedPlayer(req);
  if (!player) {
    return res.status(401).json({ ok: false, error: "unauthorized" });
  }
  req.player = player;
  next();
}

function playerSkinId(player) {
  return (player.appearance && player.appearance.skinId) ||
    player.skinId ||
    (player.snapshot && player.snapshot.appearance && player.snapshot.appearance.skinId) ||
    "street_brawler";
}

function publicPlayer(player) {
  reconcilePlayerGuilds(player);
  const skinId = playerSkinId(player);
  return {
    playerId: player.playerId,
    profileSlot: player.profileSlot || 1,
    displayName: player.displayName,
    level: player.level || 1,
    status: player.status || "online",
    currentScene: player.currentScene || "Home",
    primaryGuild: (player.guilds || [])[0] || null,
    skinId,
    appearance: { skinId },
  };
}

function accountProfiles(account) {
  return (account && Array.isArray(account.playerIds) ? account.playerIds : [])
    .map((id) => publicPlayer(state.players[id]))
    .filter(Boolean);
}

function issueAccountSession(account, playerId) {
  const accessToken = makeToken(account.accountId);
  state.tokens[accessToken] = { accountId: account.accountId, playerId };
  return accessToken;
}

function fullPlayer(player) {
  repairInflatedHp(player);
  reconcilePlayerGuilds(player);
  const snapshot = player.snapshot || {};
  return {
    ...snapshot,
    ...player,
    inventory: player.inventory || snapshot.inventory || [],
    equipped: player.equipped || snapshot.equipped || {},
    materials: player.materials || snapshot.materials || {},
    injections: player.injections || snapshot.injections || { active: {}, cooldowns: {} },
    guildVault: player.guildVault || snapshot.guildVault || {},
    guildAuction: player.guildAuction || snapshot.guildAuction || [],
    guildContributions: player.guildContributions || snapshot.guildContributions || {},
    guilds: player.guilds || [],
    weapons: player.weapons || [],
    pets: player.pets || [],
    squad: ensureSquad(player),
    tournaments: ensureTournamentState(player),
  };
}

function ensureThread(playerA, playerB) {
  const ids = [playerA.playerId, playerB.playerId].sort();
  const threadId = `thread_${ids[0]}_${ids[1]}`;
  if (!state.threads[threadId]) {
    state.threads[threadId] = {
      threadId,
      kind: "player",
      participants: ids,
      messages: [],
      updatedAt: Date.now(),
    };
  }
  return state.threads[threadId];
}

function threadSummary(thread, viewer) {
  if (thread.kind === "player") {
    const otherId = thread.participants.find((id) => id !== viewer.playerId) || thread.participants[0];
    const other = state.players[otherId];
    const last = thread.messages[thread.messages.length - 1];
    return {
      threadId: thread.threadId,
      kind: "player",
      playerId: other ? other.playerId : otherId,
      from: other ? other.displayName : "Unknown",
      lastMessage: last ? last.body : "No messages yet.",
      timeLabel: last ? last.timeLabel : "",
      unread: 0,
    };
  }

  const last = thread.messages[thread.messages.length - 1];
  return {
    threadId: thread.threadId,
    kind: thread.kind,
    from: thread.title || "System",
    lastMessage: last ? last.body : "",
    timeLabel: last ? last.timeLabel : "",
    unread: 0,
  };
}

function addFriendBoth(a, b) {
  state.friends[a.playerId] = state.friends[a.playerId] || [];
  state.friends[b.playerId] = state.friends[b.playerId] || [];
  if (!state.friends[a.playerId].includes(b.playerId)) state.friends[a.playerId].push(b.playerId);
  if (!state.friends[b.playerId].includes(a.playerId)) state.friends[b.playerId].push(a.playerId);
}

function upsertGuildOnPlayer(player, guild, role) {
  player.guilds = player.guilds || [];
  guild.memberRanks = guild.memberRanks || {};
  const normalizedRole = guild.leaderPlayerId === player.playerId ? "LEADER" : String(role || guild.memberRanks[player.playerId] || "MEMBER").toUpperCase();
  const publicEntry = { ...publicGuild(guild), role: normalizedRole || "MEMBER" };
  const existing = player.guilds.find((entry) => entry.guildId === guild.guildId);
  if (existing) {
    Object.assign(existing, publicEntry);
  } else {
    player.guilds.push(publicEntry);
  }
}

function playerJoinedGuild(player, exceptGuildId) {
  const playerId = player && player.playerId;
  if (!playerId) return null;

  const joined = Object.values(state.guilds || {}).find((guild) => {
    if (!guild || guild.guildId === exceptGuildId) return false;
    guild.members = Array.isArray(guild.members) ? guild.members : [];
    return guild.leaderPlayerId !== playerId && guild.members.includes(playerId);
  });
  if (joined) return publicGuild(joined);

  if (player.guild && player.guild.guildId && player.guild.guildId !== exceptGuildId) {
    return player.guild;
  }

  return null;
}

function mergeGuildLists(existingList, incomingList) {
  const out = [];
  const byId = new Map();
  for (const guild of [...(existingList || []), ...(incomingList || [])]) {
    if (!guild || !guild.guildId) continue;
    const prior = byId.get(guild.guildId) || {};
    byId.set(guild.guildId, { ...prior, ...guild, role: guild.role || prior.role || "Member" });
  }
  for (const guild of byId.values()) out.push(guild);
  return out;
}

function removeGuildFromPlayer(player, guildId) {
  player.guilds = Array.isArray(player.guilds)
    ? player.guilds.filter((entry) => entry.guildId !== guildId)
    : [];
  if (player.guild && player.guild.guildId === guildId) delete player.guild;
  if (player.createdGuild && player.createdGuild.guildId === guildId) delete player.createdGuild;
  if (player.snapshot) {
    player.snapshot.guilds = Array.isArray(player.snapshot.guilds)
      ? player.snapshot.guilds.filter((entry) => entry.guildId !== guildId)
      : [];
    if (player.snapshot.guild && player.snapshot.guild.guildId === guildId) delete player.snapshot.guild;
    if (player.snapshot.createdGuild && player.snapshot.createdGuild.guildId === guildId) delete player.snapshot.createdGuild;
  }
}

function reconcilePlayerGuilds(player) {
  if (!player || !player.playerId) return player;
  const guildEntries = [];
  let joinedGuild = null;
  let createdGuild = null;

  for (const guild of Object.values(state.guilds || {})) {
    if (!guild || !guild.guildId) continue;
    guild.members = Array.isArray(guild.members) ? guild.members : [];
    const isLeader = guild.leaderPlayerId === player.playerId;
    const isMember = guild.members.includes(player.playerId);
    if (!isLeader && !isMember) continue;

    guild.memberRanks = guild.memberRanks || {};
    const role = isLeader ? "LEADER" : String(guild.memberRanks[player.playerId] || "MEMBER").toUpperCase();
    const entry = { ...publicGuild(guild), role };
    guildEntries.push(entry);
    if (isLeader) {
      createdGuild = entry;
    } else if (!joinedGuild) {
      joinedGuild = entry;
    }
  }

  player.guilds = guildEntries;
  if (joinedGuild) player.guild = joinedGuild;
  else delete player.guild;
  if (createdGuild) player.createdGuild = createdGuild;
  else delete player.createdGuild;

  if (player.snapshot) {
    player.snapshot.guilds = guildEntries;
    if (joinedGuild) player.snapshot.guild = joinedGuild;
    else delete player.snapshot.guild;
    if (createdGuild) player.snapshot.createdGuild = createdGuild;
    else delete player.snapshot.createdGuild;
  }

  return player;
}

function removeDeletedPlayerFromGuilds(playerId) {
  for (const guild of Object.values(state.guilds || {})) {
    guild.members = Array.isArray(guild.members) ? guild.members.filter((id) => id !== playerId) : [];
    if (guild.leaderPlayerId === playerId) {
      guild.leaderPlayerId = guild.members[0] || null;
    }
    if (guild.contributions) delete guild.contributions[playerId];
    if (Array.isArray(guild.chat)) {
      guild.chat = guild.chat.filter((message) => message.authorPlayerId !== playerId);
    }
    if (Array.isArray(guild.auctions)) {
      guild.auctions = guild.auctions.filter((auction) => auction.sellerPlayerId !== playerId);
    }
  }
}

function publicGuild(guild) {
  guild.members = Array.isArray(guild.members) ? guild.members : [];
  ensureGuildEconomy(guild);
  const members = guild.members;
  const leader = state.players[guild.leaderPlayerId];
  const directGold = Number(guild.gold) || 0;
  const vaultedGold = Number(guild.vault && guild.vault.gold) || 0;
  return {
    guildId: guild.guildId,
    name: guild.name,
    leader: leader ? leader.displayName : "Unknown",
    leaderPlayerId: guild.leaderPlayerId,
    members: members.length,
    maxMembers: guild.maxMembers || 20,
    gold: directGold + vaultedGold,
    level: guild.level || 1,
    averageLevel: guildAverageLevel(guild),
    jailCount: publicGuildJail(guild).length,
    isPublic: guild.isPublic !== false,
    desc: guild.desc || "",
  };
}

function publicGuildMember(player, guild) {
  const snapshot = player.snapshot || {};
  const skinId = playerSkinId(player);
  return {
    playerId: player.playerId,
    name: player.displayName || snapshot.name || "Player",
    level: snapshot.level || player.level || 1,
    rank: getMemberRank(guild, player.playerId),
    online: (player.status || "online") === "online",
    skinId,
    appearance: { skinId },
  };
}

function guildMembers(guild) {
  guild.members = Array.isArray(guild.members) ? guild.members : [];
  const ids = guild.members;
  return ids.map((id) => state.players[id]).filter(Boolean).map((player) => publicGuildMember(player, guild));
}

function guildAverageLevel(guild) {
  guild.members = Array.isArray(guild.members) ? guild.members : [];
  const levels = guild.members
    .map((id) => state.players[id])
    .filter(Boolean)
    .map((player) => Number((player.snapshot && player.snapshot.level) || player.level || 1) || 1);
  if (levels.length === 0) return Number(guild.level) || 1;
  return Math.max(1, Math.round(levels.reduce((sum, level) => sum + level, 0) / levels.length));
}

const GUILD_JAIL_MS = 24 * 60 * 60 * 1000;

function ensureGuildJail(guild) {
  guild.jail = Array.isArray(guild.jail) ? guild.jail : [];
  const now = Date.now();
  guild.jail = guild.jail.filter((entry) => Date.parse(entry.releaseAt || "") > now);
  return guild.jail;
}

function publicGuildJail(guild) {
  return ensureGuildJail(guild).map((entry) => ({
    playerId: entry.playerId,
    name: entry.name || "Player",
    capturedAt: entry.capturedAt,
    releaseAt: entry.releaseAt,
    taxRate: entry.taxRate || 0.10,
  }));
}

function activeGuildJailForPlayer(playerId) {
  const now = Date.now();
  for (const guild of Object.values(state.guilds || {})) {
    const jail = ensureGuildJail(guild);
    const entry = jail.find((item) => item.playerId === playerId && Date.parse(item.releaseAt || "") > now);
    if (entry) return { guild, entry };
  }
  return null;
}

function jailPlayerInGuild(guild, player) {
  const jail = ensureGuildJail(guild);
  const now = Date.now();
  const releaseAt = new Date(now + GUILD_JAIL_MS).toISOString();
  let entry = jail.find((item) => item.playerId === player.playerId);
  if (!entry) {
    entry = { playerId: player.playerId };
    jail.push(entry);
  }
  entry.name = player.displayName || "Player";
  entry.capturedAt = new Date(now).toISOString();
  entry.releaseAt = releaseAt;
  entry.taxRate = 0.10;
  return entry;
}

function rollGuildLootReward(player, guild) {
  const rewards = [
    { type: "gold", key: "gold", name: "Gold", amount: 500 },
    { type: "material", key: "crystal_green", name: "Green Crystal", amount: 1 },
    { type: "material", key: "crystal_blue", name: "Blue Crystal", amount: 1 },
    { type: "material", key: "crystal_purple", name: "Purple Crystal", amount: 1 },
    { type: "material", key: "crystal_orange", name: "Orange Crystal", amount: 1 },
    { type: "material", key: "augment_attack", name: "Atk Augment", amount: 1 },
    { type: "material", key: "augment_defense", name: "Def Augment", amount: 1 },
    { type: "material", key: "augment_speed", name: "Spd Augment", amount: 1 },
    { type: "material", key: "augment_health", name: "HP Augment", amount: 1 },
  ];
  const reward = { ...rewards[Math.floor(Math.random() * rewards.length)] };
  const before = {
    playerGold: Number(player.gold) || 0,
    guildGold: Number(guild.gold) || 0,
    materialQty: reward.key && player.materials ? Number(player.materials[reward.key]) || 0 : 0,
  };
  if (reward.type === "gold") {
    player.gold = (Number(player.gold) || 0) + reward.amount;
    guild.gold = Math.max(0, (Number(guild.gold) || 0) - reward.amount);
  } else {
    player.materials = player.materials || {};
    player.materials[reward.key] = (Number(player.materials[reward.key]) || 0) + reward.amount;
  }
  addAuditLog({
    player,
    action: "guild_loot_success",
    before,
    after: {
      playerGold: Number(player.gold) || 0,
      guildGold: Number(guild.gold) || 0,
      materialQty: reward.key && player.materials ? Number(player.materials[reward.key]) || 0 : 0,
    },
    reason: "Guild loot victory reward",
    source: "guild_loot",
    meta: { guildId: guild.guildId, guildName: guild.name, reward },
  });
  return reward;
}

function lootDefenderSnapshot(player, index) {
  const snap = fullPlayer(player);
  const equipped = snap.equipped || {};
  return {
    ...snap,
    id: `enemy:leader:${index + 1}`,
    playerId: snap.playerId,
    name: snap.displayName || snap.name || `Defender ${index + 1}`,
    displayName: snap.displayName || snap.name || `Defender ${index + 1}`,
    visualId: playerSkinId(player),
    skinId: playerSkinId(player),
    level: Number(snap.level) || 1,
    attack: Number(snap.attack) || 100,
    defense: Number(snap.defense) || 100,
    speed: Number(snap.speed) || 100,
    hp: Number(snap.hp) || 100,
    equipped,
    pets: snap.pets || (equipped && equipped.pets) || [],
    currentWeaponIndex: snap.currentWeaponIndex || 1,
    weaponUsesLeft: snap.weaponUsesLeft,
  };
}

function guildWarFighterSnapshot(player, index, side) {
  const snap = fullPlayer(player);
  const equipped = snap.equipped || {};
  const idPrefix = side === "player" ? "player" : "enemy";
  return {
    ...snap,
    id: `${idPrefix}:leader:${index + 1}`,
    playerId: snap.playerId,
    name: snap.displayName || snap.name || `Fighter ${index + 1}`,
    displayName: snap.displayName || snap.name || `Fighter ${index + 1}`,
    visualId: playerSkinId(player),
    skinId: playerSkinId(player),
    level: Number(snap.level) || 1,
    attack: Number(snap.attack) || 100,
    defense: Number(snap.defense) || 100,
    speed: Number(snap.speed) || 100,
    hp: Number(snap.hp) || 100,
    equipped: { ...equipped, pets: [] },
    pets: [],
    currentWeaponIndex: snap.currentWeaponIndex || 1,
    weaponUsesLeft: snap.weaponUsesLeft,
    spells: snap.spells || [],
  };
}

function ensureGuildWars(guild) {
  guild.wars = Array.isArray(guild.wars) ? guild.wars : [];
  return guild.wars;
}

const GUILD_WAR_PREP_MS = 60 * 1000;

function materializeReadyGuildWars() {
  const now = Date.now();
  let changed = false;
  for (const guild of Object.values(state.guilds || {})) {
    for (const war of ensureGuildWars(guild)) {
      if ((war.status || "active") === "pending" && Date.parse(war.readyAt || "") <= now) {
        war.status = "active";
        changed = true;
      }
    }
  }
  return changed;
}

function leaderGuildForPlayer(player) {
  if (!player) return null;
  return Object.values(state.guilds || {}).find((guild) => guild.leaderPlayerId === player.playerId) || null;
}

function pendingWarForViewerGuild(targetGuild, viewerPlayer) {
  const leaderGuild = leaderGuildForPlayer(viewerPlayer);
  if (!leaderGuild || !targetGuild || leaderGuild.guildId === targetGuild.guildId) return null;
  const pending = ensureGuildWars(leaderGuild)
    .filter((war) => (war.status || "active") === "pending")
    .filter((war) => war.attackerGuildId === leaderGuild.guildId && war.defenderGuildId === targetGuild.guildId)
    .sort((a, b) => Date.parse(b.createdAt || 0) - Date.parse(a.createdAt || 0))[0];
  return pending ? publicGuildWar(pending) : null;
}

function pickGuildWarTeam(guild, side, seed) {
  guild.members = Array.isArray(guild.members) ? guild.members : [];
  const rand = createSeededRandom(seed);
  const onlinePool = guild.members
    .map((id) => state.players[id])
    .filter(Boolean)
    .filter((player) => (player.status || "online") === "online");
  const pool = onlinePool.length > 0 ? onlinePool : guild.members.map((id) => state.players[id]).filter(Boolean);
  const picked = pickManyUnique(rand, pool, 5);
  return picked.map((player, index) => guildWarFighterSnapshot(player, index, side));
}

function publicGuildWar(war) {
  return {
    warId: war.warId,
    createdAt: war.createdAt,
    readyAt: war.readyAt,
    readyAtMs: Date.parse(war.readyAt || "") || null,
    status: war.status || "active",
    attackerGuildId: war.attackerGuildId,
    attackerGuildName: war.attackerGuildName,
    defenderGuildId: war.defenderGuildId,
    defenderGuildName: war.defenderGuildName,
    attackers: war.attackers || [],
    defenders: war.defenders || [],
  };
}

function isGuildMember(guild, playerId) {
  guild.members = Array.isArray(guild.members) ? guild.members : [];
  return guild.members.includes(playerId);
}

function visibleGuildMessages(guild, viewerPlayerId) {
  const messages = state.guildChats[guild.guildId] || [];
  if (isGuildMember(guild, viewerPlayerId)) return messages;
  return messages.filter((message) => message.private !== true);
}

function createSeededRandom(seed) {
  let value = 0;
  const source = String(seed || "seed");
  for (let i = 0; i < source.length; i += 1) {
    value = ((value * 31) + source.charCodeAt(i)) >>> 0;
  }
  if (value === 0) value = 0x9e3779b9;
  return function rand() {
    value ^= value << 13;
    value ^= value >>> 17;
    value ^= value << 5;
    value >>>= 0;
    return (value & 0xffffffff) / 0x100000000;
  };
}

function randInt(rand, min, max) {
  const lo = Math.floor(min);
  const hi = Math.floor(max);
  return lo + Math.floor(rand() * (hi - lo + 1));
}

function pickOne(rand, list) {
  if (!Array.isArray(list) || list.length === 0) return null;
  return list[randInt(rand, 0, list.length - 1)];
}

function pickManyUnique(rand, list, count) {
  const pool = Array.isArray(list) ? [...list] : [];
  const out = [];
  const want = Math.max(0, Math.min(pool.length, Math.floor(count || 0)));
  while (out.length < want && pool.length > 0) {
    const index = randInt(rand, 0, pool.length - 1);
    out.push(pool.splice(index, 1)[0]);
  }
  return out;
}

const BOT_GEAR = {
  weapons: [
    { id: "dagger_basic", level: 1 }, { id: "short_sword", level: 4 }, { id: "crow_bar", level: 5 },
    { id: "machette_basic", level: 6 }, { id: "extended_spear", level: 6 }, { id: "katana_speed", level: 7 },
    { id: "scrap_gun", level: 10 }, { id: "scrap_trident", level: 10 }, { id: "heavy_axe", level: 12 },
    { id: "stone_hammer", level: 13 }, { id: "monosickle", level: 13 }, { id: "scrap_sniper", level: 14 },
    { id: "pipe_crusher", level: 14 }, { id: "heavy_sword", level: 15 }, { id: "shield_bash", level: 17 },
    { id: "executioner", level: 19 }, { id: "green_plasma_blade", level: 20 }, { id: "tech_hammer", level: 20 },
  ],
  armor: {
    helmet: [
      { id: "leather_helmet", level: 2 }, { id: "combat_helmet", level: 12 }, { id: "riot_helmet", level: 16 },
    ],
    chest: [
      { id: "leather_chest", level: 5 }, { id: "combat_chest", level: 14 }, { id: "riot_chest", level: 20 },
    ],
    gloves: [
      { id: "leather_gloves", level: 4 }, { id: "combat_gloves", level: 10 }, { id: "riot_gloves", level: 14 },
    ],
    boots: [
      { id: "leather_boots", level: 5 }, { id: "combat_boots", level: 13 }, { id: "riot_boots", level: 18 },
    ],
  },
  accessories: {
    necklace: [
      { id: "attack_necklace", level: 5 }, { id: "defense_necklace", level: 5 }, { id: "health_necklace", level: 5 }, { id: "speed_necklace", level: 5 },
    ],
    ring: [
      { id: "attack_ring", level: 8 }, { id: "defense_ring", level: 8 }, { id: "health_ring", level: 8 }, { id: "speed_ring", level: 8 },
    ],
    charm: [
      { id: "attack_charm", level: 12 }, { id: "defense_charm", level: 12 }, { id: "health_charm", level: 12 }, { id: "speed_charm", level: 12 },
    ],
  },
  pets: [
    { id: "cat", level: 3 }, { id: "capybara", level: 7 }, { id: "dog", level: 8 }, { id: "parrot", level: 9 },
    { id: "cheetah", level: 10 }, { id: "panda", level: 10 }, { id: "horse", level: 12 }, { id: "wasp", level: 13 },
    { id: "snake", level: 14 }, { id: "raccoon", level: 14 }, { id: "turtle", level: 14 }, { id: "rhino", level: 15 },
    { id: "guar", level: 16 }, { id: "hippo", level: 18 }, { id: "tiger", level: 24 }, { id: "alligator", level: 26 },
    { id: "polar_bear", level: 26 }, { id: "elephant", level: 28 },
  ],
  spells: [
    { id: "counter", level: 2 }, { id: "two_piece_combo", level: 10 }, { id: "wrath", level: 11 },
    { id: "last_stand", level: 13 }, { id: "stun_grenade", level: 15 }, { id: "call_a_friend", level: 18 },
    { id: "ultimate_trainer", level: 20 },
  ],
};

function eligibleByLevel(list, level) {
  return (list || []).filter((entry) => (entry.level || 1) <= level);
}

function pickNearLevel(rand, list, level) {
  const pool = eligibleByLevel(list, level);
  if (pool.length === 0) return null;
  const weighted = [];
  for (const entry of pool) {
    const gap = Math.max(0, level - (entry.level || 1));
    let weight = Math.max(0.12, 2.1 - (gap * 0.15));
    if (entry.level >= level - 2) weight += 0.9;
    else if (entry.level >= level - 5) weight += 0.35;
    weighted.push({ entry, weight });
  }
  const total = weighted.reduce((sum, row) => sum + row.weight, 0);
  let roll = rand() * total;
  for (const row of weighted) {
    roll -= row.weight;
    if (roll <= 0) return row.entry;
  }
  return weighted[weighted.length - 1].entry;
}

function buildServerBot({ difficulty, targetLevel, idx, requesterLevel }) {
  const seed = `bot:${difficulty}:${targetLevel}:${idx}`;
  const rand = createSeededRandom(seed);
  const visualIds = ["corp_enforcer", "street_brawler", "street_fighter", "street_punk", "street_fighter_f", "street_punk_f"];
  const botNames = ["ByteRift", "ChromeHex", "NullVex", "CircuitKid", "IronPulse", "AshVector", "NeonFang", "GridShade"];
  const level = Math.max(1, Number(targetLevel) || 1);
  const levelScale = Math.max(0, level - 1);

  const weaponPool = eligibleByLevel(BOT_GEAR.weapons, level).map((row) => row.id);
  const weaponCount = Math.max(1, Math.min(3, (level >= 20 ? 3 : level >= 10 ? 2 : 1) + (rand() < 0.33 ? 1 : 0)));
  const weapons = pickManyUnique(rand, weaponPool, weaponCount);

  const armor = {};
  for (const slot of ["helmet", "chest", "gloves", "boots"]) {
    const choice = pickNearLevel(rand, BOT_GEAR.armor[slot], level);
    if (choice) armor[slot] = choice.id;
  }

  const accessories = {};
  if (level >= 5) {
    const necklace = pickNearLevel(rand, BOT_GEAR.accessories.necklace, level);
    if (necklace) accessories.necklace = necklace.id;
  }
  if (level >= 8) {
    const ring = pickNearLevel(rand, BOT_GEAR.accessories.ring, level);
    if (ring) accessories.ring = ring.id;
  }
  if (level >= 12) {
    const charm = pickNearLevel(rand, BOT_GEAR.accessories.charm, level);
    if (charm) accessories.charm = charm.id;
  }

  const petSlots = level >= 20 ? 3 : 2;
  const petCount = Math.min(petSlots, Math.max(1, (level >= 14 ? 2 : 1) + (rand() < 0.35 ? 1 : 0)));
  const petChoices = [];
  const petPool = [...eligibleByLevel(BOT_GEAR.pets, level)];
  while (petChoices.length < petCount && petPool.length > 0) {
    const choice = pickNearLevel(rand, petPool, level);
    if (!choice) break;
    petChoices.push(choice.id);
    const removeIndex = petPool.findIndex((entry) => entry.id === choice.id);
    if (removeIndex >= 0) petPool.splice(removeIndex, 1);
  }

  const spells = [];
  for (const spell of BOT_GEAR.spells) {
    if (level < spell.level) continue;
    const gap = level - spell.level;
    const chance = Math.min(0.92, 0.32 + (gap * 0.05));
    if (rand() < chance) spells.push(spell.id);
  }
  if (level >= 10 && spells.length === 0) {
    const fallback = eligibleByLevel(BOT_GEAR.spells, level);
    const pick = pickOne(rand, fallback);
    if (pick) spells.push(pick.id);
  }

  const atk = 95 + (levelScale * 8) + randInt(rand, -6, 12);
  const def = 92 + (levelScale * 8) + randInt(rand, -6, 10);
  const spd = 90 + (levelScale * 7) + randInt(rand, -8, 12);
  const hp = 105 + (levelScale * 12) + randInt(rand, -12, 18);
  const difficultyScale = { bully: 0.92, easy: 0.96, casual: 1.00, normal: 1.00, hard: 1.08, extreme: 1.16 }[difficulty] || 1.0;
  const botStatScale = 0.90;
  const requesterBias = requesterLevel && level > requesterLevel ? 1.02 : 1.0;

  return {
    playerId: `bot_${difficulty}_${level}_${idx}`,
    displayName: `${botNames[idx % botNames.length]} ${level}`,
    level,
    skinId: visualIds[idx % visualIds.length],
    visualId: visualIds[idx % visualIds.length],
    bot: true,
    attack: Math.max(40, Math.floor(atk * difficultyScale * requesterBias * botStatScale)),
    defense: Math.max(40, Math.floor(def * difficultyScale * botStatScale)),
    speed: Math.max(40, Math.floor(spd * difficultyScale * botStatScale)),
    hp: Math.max(80, Math.floor(hp * difficultyScale * botStatScale)),
    equipped: {
      weapons,
      armor,
      accessories,
      pets: petChoices,
    },
    pets: petChoices,
    spells,
    currentWeaponIndex: 1,
    weaponUsesLeft: null,
  };
}

function ensureGuildEconomy(guild) {
  guild.vault = guild.vault || {};
  guild.vaultItems = guild.vaultItems || {};
  guild.contributions = guild.contributions || {};
  guild.auctions = Array.isArray(guild.auctions) ? guild.auctions : [];
  return guild;
}

function contributionTotal(row) {
  return (row.itemCount || 0) + (row.gold || 0);
}

function publicGuildContribution(row) {
  return {
    playerId: row.playerId,
    name: row.name || "Player",
    rank: row.rank || "MEMBER",
    items: row.items || {},
    itemCount: row.itemCount || 0,
    gold: row.gold || 0,
    total: row.total || contributionTotal(row),
    lastAt: row.lastAt || "",
  };
}

function publicGuildEconomy(guild) {
  ensureGuildEconomy(guild);
  guild.legacyVaultMigrated = guild.legacyVaultMigrated || {};
  let migrated = false;
  for (const playerId of Array.isArray(guild.members) ? guild.members : []) {
    if (guild.legacyVaultMigrated[playerId]) continue;
    const player = state.players[playerId];
    const legacyVault = player && (player.guildVault || player.snapshot && player.snapshot.guildVault);
    if (legacyVault && typeof legacyVault === "object") {
      for (const [key, qtyValue] of Object.entries(legacyVault)) {
        const qty = Math.max(0, Math.floor(Number(qtyValue) || 0));
        if (!key || qty <= 0) continue;
        guild.vault[key] = (guild.vault[key] || 0) + qty;
        guild.vaultItems[key] = guild.vaultItems[key] || { key, name: key, sprite: "", color: null, type: "" };
        migrated = true;
      }
    }

    const legacyContributions = player && (player.guildContributions || player.snapshot && player.snapshot.guildContributions);
    if (legacyContributions && typeof legacyContributions === "object") {
      for (const row of Object.values(legacyContributions)) {
        if (!row || typeof row !== "object") continue;
        const id = row.playerId || playerId;
        const existing = guild.contributions[id] || {
          playerId: id,
          name: row.name || player.displayName || "Player",
          rank: getMemberRank(guild, id),
          items: {},
          itemCount: 0,
          gold: 0,
          total: 0,
        };
        existing.items = { ...(existing.items || {}), ...(row.items || {}) };
        existing.itemCount = Math.max(existing.itemCount || 0, Number(row.itemCount) || 0);
        existing.gold = Math.max(existing.gold || 0, Number(row.gold) || 0);
        existing.total = Math.max(existing.total || 0, Number(row.total) || contributionTotal(existing));
        existing.lastAt = existing.lastAt || row.lastAt || "";
        guild.contributions[id] = existing;
        migrated = true;
      }
    }

    guild.legacyVaultMigrated[playerId] = true;
    migrated = true;
  }
  if (migrated) saveState();

  const contributions = Object.values(guild.contributions)
    .map(publicGuildContribution)
    .sort((a, b) => (b.total || 0) - (a.total || 0));

  return {
    guildId: guild.guildId,
    vault: guild.vault,
    vaultItems: guild.vaultItems,
    contributions,
    auctions: guild.auctions,
  };
}

function getMemberRank(guild, playerId) {
  if (guild.leaderPlayerId === playerId) return "LEADER";
  guild.memberRanks = guild.memberRanks || {};
  return String(guild.memberRanks[playerId] || "MEMBER").toUpperCase();
}

function addGuildContribution(guild, player, item, qty) {
  ensureGuildEconomy(guild);
  const key = item.key;
  const row = guild.contributions[player.playerId] || {
    playerId: player.playerId,
    name: player.displayName || "Player",
    rank: getMemberRank(guild, player.playerId),
    items: {},
    itemCount: 0,
    gold: 0,
    total: 0,
  };

  row.name = player.displayName || row.name || "Player";
  row.rank = getMemberRank(guild, player.playerId);
  row.items = row.items || {};
  row.items[key] = (row.items[key] || 0) + qty;
  if (key === "gold") {
    row.gold = (row.gold || 0) + qty;
  } else {
    row.itemCount = (row.itemCount || 0) + qty;
  }
  row.total = contributionTotal(row);
  row.lastAt = timestampLabel();
  guild.contributions[player.playerId] = row;
}

function removePlayerItemForDonation(player, item, qty) {
  const key = item.key;
  if (key === "gold") {
    if ((player.gold || 0) < qty) return false;
    player.gold -= qty;
    return true;
  }

  const materialKeys = player.materials || {};
  if (Object.prototype.hasOwnProperty.call(materialKeys, key)) {
    if ((player.materials[key] || 0) < qty) return false;
    player.materials[key] -= qty;
    return true;
  }

  player.inventory = Array.isArray(player.inventory) ? player.inventory : [];
  let removed = 0;
  for (let index = player.inventory.length - 1; index >= 0 && removed < qty; index -= 1) {
    if (player.inventory[index] === key) {
      player.inventory.splice(index, 1);
      removed += 1;
    }
  }
  return removed === qty;
}

function isMaterialLikeItem(key, type) {
  const normalizedType = String(type || "").toLowerCase();
  return normalizedType === "material" ||
    normalizedType === "crystal" ||
    normalizedType === "augment" ||
    String(key || "").startsWith("crystal_") ||
    String(key || "").startsWith("augment_") ||
    key === "scrap" ||
    key === "coil" ||
    key === "chip";
}

function grantPlayerItem(player, item, qty) {
  const key = String(item && (item.key || item.itemId) || "").trim();
  const amount = Math.max(1, Math.floor(Number(qty) || 1));
  if (!key) return false;
  if (key === "gold") {
    player.gold = (Number(player.gold) || 0) + amount;
    return true;
  }
  if (isMaterialLikeItem(key, item && item.type)) {
    player.materials = player.materials || {};
    player.materials[key] = (Number(player.materials[key]) || 0) + amount;
    return true;
  }
  player.inventory = Array.isArray(player.inventory) ? player.inventory : [];
  for (let index = 0; index < amount; index += 1) player.inventory.push(key);
  return true;
}

function addItemToGuildVault(guild, item, qty) {
  ensureGuildEconomy(guild);
  guild.vault[item.key] = (guild.vault[item.key] || 0) + qty;
  guild.vaultItems[item.key] = {
    key: item.key,
    name: item.name || item.key,
    sprite: item.sprite || item.icon || "",
    color: item.color || null,
    type: item.type || "",
  };
}

function decrementGuildVault(guild, key, qty) {
  ensureGuildEconomy(guild);
  if ((guild.vault[key] || 0) < qty) return false;
  guild.vault[key] -= qty;
  if (guild.vault[key] <= 0) delete guild.vault[key];
  return true;
}

app.get("/", (req, res) => {
  res.json({ message: "Pixel Wars server online" });
});

app.get("/health", (req, res) => {
  res.json({ ok: true, service: "pixel-wars-server", routeVersion: "notifications-v1", time: new Date().toISOString() });
});

app.get("/db-test", async (req, res) => {
  try {
    const result = await pool.query("SELECT NOW()");
    res.json({ message: "Database connected!", time: result.rows[0].now });
  } catch (error) {
    res.status(500).json({ message: "Database connection failed", error: error.message });
  }
});

function requireDebugAccess(req, res, next) {
  const token = String(process.env.DEBUG_TOKEN || "").trim();
  const provided = String(req.headers["x-debug-token"] || req.query.debugToken || "").trim();
  const ip = String(req.ip || req.socket && req.socket.remoteAddress || "");
  const isLocal = ip === "127.0.0.1" || ip === "::1" || ip === "::ffff:127.0.0.1";
  if (isLocal || (token && provided === token)) return next();
  return res.status(403).json({ ok: false, error: "debug_access_denied" });
}

app.get("/debug/players", requireDebugAccess, (req, res) => {
  const players = Object.values(state.players || {}).map((player) => ({
    playerId: player.playerId,
    name: player.displayName,
    level: (player.snapshot && player.snapshot.level) || player.level || 1,
    gold: Number(player.gold) || 0,
    diamonds: Number(player.diamonds) || 0,
    guilds: player.guilds || [],
    materials: player.materials || {},
    currentScene: player.currentScene || "",
  }));
  res.json({ ok: true, count: players.length, players });
});

app.get("/debug/state", requireDebugAccess, (req, res) => {
  res.json({
    ok: true,
    persistence: useDatabaseState ? "postgres" : "file",
    counts: {
      accounts: Object.keys(state.accounts || {}).length,
      players: Object.keys(state.players || {}).length,
      guilds: Object.keys(state.guilds || {}).length,
      threads: Object.keys(state.threads || {}).length,
      notifications: Object.keys(state.notifications || {}).length,
    },
    state,
  });
});

app.get("/debug/guilds", requireDebugAccess, (req, res) => {
  const guilds = Object.values(state.guilds || {}).map((guild) => ({
    ...publicGuild(guild),
    vault: publicGuildEconomy(guild).vault,
    jail: publicGuildJail(guild),
  }));
  res.json({ ok: true, count: guilds.length, guilds });
});

app.get("/debug/guilds/:guildId/vault", requireDebugAccess, (req, res) => {
  const guild = state.guilds[req.params.guildId];
  if (!guild) return res.status(404).json({ ok: false, error: "guild_not_found" });
  res.json({ ok: true, guild: publicGuild(guild), economy: publicGuildEconomy(guild) });
});

app.get("/debug/jailed", requireDebugAccess, (req, res) => {
  const jailed = [];
  for (const guild of Object.values(state.guilds || {})) {
    for (const entry of publicGuildJail(guild)) {
      jailed.push({
        guildId: guild.guildId,
        guildName: guild.name,
        ...entry,
      });
    }
  }
  res.json({ ok: true, count: jailed.length, jailed });
});

app.get("/debug/audit", requireDebugAccess, (req, res) => {
  const limit = Math.max(1, Math.min(200, Math.floor(Number(req.query.limit) || 50)));
  const action = String(req.query.action || "").trim();
  const playerId = String(req.query.playerId || "").trim();
  let logs = Array.isArray(state.auditLogs) ? state.auditLogs : [];
  if (action) logs = logs.filter((entry) => entry.action === action);
  if (playerId) logs = logs.filter((entry) => entry.playerId === playerId);
  res.json({ ok: true, count: logs.length, logs: logs.slice(0, limit) });
});

function registerOrLogin(req, res) {
  const requestedDisplayName = String(req.body.displayName || req.body.name || "Player").trim().slice(0, 24);
  const header = req.headers.authorization || "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : null;
  const tokenContext = token && state.tokens[token];
  const authedAccountId = typeof tokenContext === "string" ? tokenContext : tokenContext && tokenContext.accountId;
  const userId = String(req.body.userId || req.body.username || req.body.accountKey || req.body.deviceId || "").trim().slice(0, 32);
  const password = String(req.body.password || "");
  const accountKey = slug(req.body.accountKey || userId || req.body.deviceId || req.body.accountId || requestedDisplayName);
  const profileSlot = clampProfileSlot(req.body.profileSlot);
  const requestedAccountId = `account_${accountKey || slug(requestedDisplayName) || Date.now()}`;
  const accountId = authedAccountId || requestedAccountId;
  let playerId = `player_${accountKey || slug(requestedDisplayName) || Date.now()}_slot_${profileSlot}`;
  const isRegisterRoute = String(req.path || "").endsWith("/register");
  const isLoginRoute = String(req.path || "").endsWith("/login");

  let account = normalizeAccount(state.accounts[accountId]);
  if (!account) {
    const matchedAccount = findAccountByHandle(userId || accountKey);
    if (matchedAccount) {
      account = matchedAccount;
    }
  }

  if (!account) {
    if (isLoginRoute && !authedAccountId) {
      return res.status(404).json({ ok: false, error: "account_not_found" });
    }
    if (!password) {
      return res.status(400).json({ ok: false, error: "password_required" });
    }
    if (isDisplayNameTaken(requestedDisplayName)) {
      return res.status(409).json({ ok: false, error: "display_name_taken" });
    }
    account = {
      accountId,
      accountKey,
      userId: userId || accountKey,
      displayName: requestedDisplayName,
      activePlayerId: playerId,
      playerId,
      playerIds: [],
      profileSlots: {},
      createdAt: new Date().toISOString(),
    };
    setAccountPassword(account, password);
    state.accounts[accountId] = account;
  } else if (isRegisterRoute && !authedAccountId) {
    return res.status(409).json({ ok: false, error: "account_exists" });
  } else if (!authedAccountId) {
    if (!verifyPassword(account, password)) {
      return res.status(401).json({ ok: false, error: "wrong_password" });
    }
  }

  playerId = `player_${account.accountKey || accountKey || slug(requestedDisplayName) || Date.now()}_slot_${profileSlot}`;

  let activePlayerId = account.profileSlots[String(profileSlot)];
  if (!activePlayerId) {
    if (account.playerIds.length >= 5) {
      return res.status(400).json({ ok: false, error: "max_profiles_reached" });
    }
    activePlayerId = playerId;
    account.profileSlots[String(profileSlot)] = activePlayerId;
    account.playerIds.push(activePlayerId);
    createPlayer(account, activePlayerId, nextProfileDisplayName(), profileSlot);
  }

  const activePlayer = state.players[activePlayerId] || createPlayer(account, activePlayerId, nextProfileDisplayName(), profileSlot);
  activePlayer.profileSlot = profileSlot;
  activePlayer.status = "online";

  account.displayName = account.displayName || requestedDisplayName;
  account.activePlayerId = activePlayerId;
  account.playerId = activePlayerId;

  const accessToken = issueAccountSession(account, activePlayerId);
  saveState();
  res.json({
    ok: true,
    accountKey: account.accountKey || accountKey,
    userId: account.userId || userId || accountKey,
    accountId: account.accountId,
    profileSlot,
    playerId: activePlayerId,
    accessToken,
    refreshToken: accessToken,
    player: fullPlayer(activePlayer),
    profiles: accountProfiles(account),
  });
}

app.post("/v1/auth/register", registerOrLogin);
app.post("/v1/auth/login", registerOrLogin);

app.get("/v1/player/me", requirePlayer, (req, res) => {
  res.json({ ok: true, player: fullPlayer(req.player) });
});

app.get("/v1/account/profiles", requirePlayer, (req, res) => {
  const account = normalizeAccount(state.accounts[req.player.accountId]);
  const profiles = accountProfiles(account);
  res.json({ ok: true, profiles });
});

app.post("/v1/account/profiles", requirePlayer, (req, res) => {
  const account = normalizeAccount(state.accounts[req.player.accountId]);
  if (!account) return res.status(404).json({ ok: false, error: "account_not_found" });

  const profileSlot = clampProfileSlot(req.body && req.body.profileSlot);
  const slotKey = String(profileSlot);
  let playerId = account.profileSlots[slotKey];

  if (!playerId) {
    if (account.playerIds.length >= 5) {
      return res.status(400).json({ ok: false, error: "max_profiles_reached" });
    }
    playerId = `player_${account.accountKey || slug(account.userId) || Date.now()}_slot_${profileSlot}`;
    account.profileSlots[slotKey] = playerId;
    account.playerIds.push(playerId);
    createPlayer(account, playerId, nextProfileDisplayName(), profileSlot);
  }

  const player = state.players[playerId] || createPlayer(account, playerId, nextProfileDisplayName(), profileSlot);
  player.profileSlot = profileSlot;
  player.status = "online";
  account.activePlayerId = playerId;
  account.playerId = playerId;

  const accessToken = issueAccountSession(account, playerId);
  saveState();
  res.json({
    ok: true,
    accountId: account.accountId,
    accountKey: account.accountKey,
    userId: account.userId,
    profileSlot,
    playerId,
    accessToken,
    refreshToken: accessToken,
    player: fullPlayer(player),
    profiles: accountProfiles(account),
  });
});

app.post("/v1/account/profiles/select", requirePlayer, (req, res) => {
  const account = normalizeAccount(state.accounts[req.player.accountId]);
  if (!account) return res.status(404).json({ ok: false, error: "account_not_found" });

  const profileSlot = clampProfileSlot(req.body && req.body.profileSlot);
  const playerId = account.profileSlots[String(profileSlot)];
  if (!playerId) return res.status(404).json({ ok: false, error: "profile_not_found" });

  const player = state.players[playerId];
  if (!player) return res.status(404).json({ ok: false, error: "player_not_found" });

  player.profileSlot = profileSlot;
  player.status = "online";
  account.activePlayerId = playerId;
  account.playerId = playerId;

  const accessToken = issueAccountSession(account, playerId);
  saveState();
  res.json({
    ok: true,
    accountId: account.accountId,
    accountKey: account.accountKey,
    userId: account.userId,
    profileSlot,
    playerId,
    accessToken,
    refreshToken: accessToken,
    player: fullPlayer(player),
    profiles: accountProfiles(account),
  });
});

app.delete("/v1/account/profiles/:profileSlot", requirePlayer, (req, res) => {
  const account = normalizeAccount(state.accounts[req.player.accountId]);
  if (!account) return res.status(404).json({ ok: false, error: "account_not_found" });

  const profileSlot = clampProfileSlot(req.params.profileSlot);
  const slotKey = String(profileSlot);
  const playerId = account.profileSlots[slotKey];
  if (!playerId) return res.status(404).json({ ok: false, error: "profile_not_found" });

  delete account.profileSlots[slotKey];
  account.playerIds = account.playerIds.filter((id) => id !== playerId);
  removeDeletedPlayerFromGuilds(playerId);
  delete state.players[playerId];
  delete state.friends[playerId];

  for (const [token, context] of Object.entries(state.tokens || {})) {
    const contextPlayerId = typeof context === "object" ? context.playerId : null;
    if (contextPlayerId === playerId) delete state.tokens[token];
  }

  const nextPlayerId = account.playerIds[0] || null;
  account.activePlayerId = nextPlayerId;
  account.playerId = nextPlayerId;
  saveState();

  const profiles = account.playerIds.map((id) => state.players[id]).filter(Boolean).map(publicPlayer);
  res.json({ ok: true, deletedPlayerId: playerId, profileSlot, profiles });
});

app.patch("/v1/player/me", requirePlayer, (req, res) => {
  const p = req.player;
  const body = req.body || {};
  if (body.renameProfile === true) {
    const requestedName = String(body.name || body.displayName || p.displayName || "Player").trim().slice(0, 24) || p.displayName || "Player";
    if (normalizeHandle(requestedName) !== normalizeHandle(p.displayName || "") && isDisplayNameTaken(requestedName, p.playerId)) {
      return res.status(409).json({ ok: false, error: "display_name_taken" });
    }
    p.displayName = requestedName;
  }
  p.level = body.level || p.level || 1;
  p.gold = Number.isFinite(Number(body.gold)) ? Number(body.gold) : (p.gold || 0);
  p.diamonds = Number.isFinite(Number(body.diamonds)) ? Number(body.diamonds) : (p.diamonds || 0);
  p.attack = Number.isFinite(Number(body.attack)) ? Number(body.attack) : p.attack;
  p.defense = Number.isFinite(Number(body.defense)) ? Number(body.defense) : p.defense;
  p.speed = Number.isFinite(Number(body.speed)) ? Number(body.speed) : p.speed;
  p.hp = Number.isFinite(Number(body.hp)) ? Number(body.hp) : p.hp;
  repairInflatedHp(p);
  p.currentScene = body.currentScene || p.currentScene || "Home";
  p.status = "online";
  p.appearance = body.appearance || p.appearance || {};
  p.skinId = (p.appearance && p.appearance.skinId) || body.skinId || p.skinId || "street_brawler";
  if (!p.appearance.skinId) p.appearance.skinId = p.skinId;
  p.weapons = body.equipped && body.equipped.weapons ? body.equipped.weapons : (body.weapons || p.weapons || []);
  p.pets = body.pets || (body.equipped && body.equipped.pets) || p.pets || [];
  p.inventory = Array.isArray(body.inventory) ? body.inventory : (p.inventory || []);
  p.equipped = body.equipped || p.equipped || {};
  p.materials = body.materials || p.materials || {};
  p.injections = body.injections || p.injections || { active: {}, cooldowns: {} };
  p.injections.active = p.injections.active || {};
  p.injections.cooldowns = p.injections.cooldowns || {};
  p.guildVault = body.guildVault || p.guildVault || {};
  p.guildAuction = Array.isArray(body.guildAuction) ? body.guildAuction : (p.guildAuction || []);
  p.guildContributions = body.guildContributions || p.guildContributions || {};
  p.notifications = Array.isArray(body.notifications) ? body.notifications.slice(0, 50) : (p.notifications || []);
  p.squad = body.squad ? mergeSquad(p.squad, body.squad) : (p.squad || { conquered: [] });
  p.tournaments = body.tournaments || p.tournaments || {};
  ensureSquad(p);
  ensureTournamentState(p);
  if (Array.isArray(body.guilds)) {
    p.guilds = mergeGuildLists(p.guilds, body.guilds);
  } else if (body.guild && body.guild.guildId) {
    upsertGuildOnPlayer(p, { guildId: body.guild.guildId, name: body.guild.name || "Guild" }, body.guild.role || "Member");
  }
  if (body.createdGuild && body.createdGuild.guildId) {
    p.createdGuild = body.createdGuild;
    upsertGuildOnPlayer(p, body.createdGuild, "Leader");
  }
  if (body.guild && body.guild.guildId) {
    p.guild = body.guild;
    upsertGuildOnPlayer(p, body.guild, body.guild.role || "Member");
  }
  p.guilds = Array.isArray(p.guilds) ? p.guilds : [];
  p.snapshot = body;
  reconcilePlayerGuilds(p);
  saveState();
  res.json({ ok: true, player: fullPlayer(p) });
});

app.get("/v1/players/search", (req, res) => {
  const query = String(req.query.q || "").trim().toLowerCase();
  if (!query) return res.json({ ok: true, query, results: [] });
  const results = Object.values(state.players)
    .filter((player) => {
      if (!query) return true;
      return (
        player.displayName.toLowerCase().includes(query) ||
        (player.guilds || []).some((guild) => guild.name.toLowerCase().includes(query))
      );
    })
    .slice(0, 20)
    .map(publicPlayer);
  res.json({ ok: true, query, results });
});

app.get("/v1/players/:playerId", (req, res) => {
  const player = state.players[req.params.playerId];
  if (!player) return res.status(404).json({ ok: false, error: "player_not_found" });
  res.json({ ok: true, player: fullPlayer(player) });
});

app.get("/v1/leaderboard/xp", (req, res) => {
  const limit = Math.max(1, Math.min(50, Math.floor(Number(req.query.limit) || 50)));
  const players = Object.values(state.players)
    .map((player) => {
      const level = Number((player.snapshot && player.snapshot.level) || player.level || 1) || 1;
      const currentXp = Number((player.snapshot && player.snapshot.xp) || player.xp || 0) || 0;
      return {
        playerId: player.playerId,
        displayName: player.displayName || "Player",
        level,
        xp: totalAccumulatedXp(level, currentXp),
        currentXp,
        status: player.status || "online",
        skinId: playerSkinId(player),
        primaryGuild: (player.guilds || [])[0] || null,
      };
    })
    .sort((a, b) => {
      if (b.xp !== a.xp) return b.xp - a.xp;
      if (b.level !== a.level) return b.level - a.level;
      return String(a.displayName).localeCompare(String(b.displayName));
    })
    .slice(0, limit);

  res.json({ ok: true, players, limit });
});

app.get("/v1/friends", requirePlayer, (req, res) => {
  const friendIds = state.friends[req.player.playerId] || [];
  const realFriends = friendIds.map((id) => state.players[id]).filter(Boolean);
  res.json({ ok: true, friends: realFriends.slice(0, 50).map(publicPlayer) });
});

app.get("/v1/friends/requests", (req, res) => {
  res.json({ ok: true, requests: [] });
});

app.post("/v1/friends/request", requirePlayer, (req, res) => {
  const target = state.players[req.body.playerId];
  if (!target) return res.status(404).json({ ok: false, error: "player_not_found" });
  addFriendBoth(req.player, target);
  if (target.playerId !== req.player.playerId) {
    pushNotification(target.playerId, {
      type: "friend",
      text: `${notificationPlayerName(req.player)} added you as a friend`,
      fromPlayerId: req.player.playerId,
      fromName: notificationPlayerName(req.player),
    });
  }
  saveState();
  res.json({ ok: true, friend: publicPlayer(target) });
});

app.get("/v1/messages/threads", requirePlayer, (req, res) => {
  const threads = Object.values(state.threads)
    .filter((thread) => thread.participants && thread.participants.includes(req.player.playerId))
    .sort((a, b) => (b.updatedAt || 0) - (a.updatedAt || 0))
    .map((thread) => threadSummary(thread, req.player));
  res.json({ ok: true, threads });
});

app.get("/v1/messages/thread/:threadId", requirePlayer, (req, res) => {
  const thread = state.threads[req.params.threadId];
  if (!thread || !thread.participants.includes(req.player.playerId)) {
    return res.status(404).json({ ok: false, error: "thread_not_found" });
  }
  res.json({ ok: true, thread: { ...threadSummary(thread, req.player), messages: thread.messages } });
});

app.post("/v1/messages/send", requirePlayer, (req, res) => {
  const target =
    state.players[req.body.toPlayerId] ||
    Object.values(state.players).find((player) => player.displayName.toLowerCase() === String(req.body.to || "").trim().toLowerCase());

  if (!target) return res.status(404).json({ ok: false, error: "player_not_found" });
  const body = String(req.body.body || req.body.message || "").trim().slice(0, 280);
  if (!body) return res.status(400).json({ ok: false, error: "empty_message" });

  const thread = ensureThread(req.player, target);
  thread.messages.push({ author: req.player.displayName, authorPlayerId: req.player.playerId, body, private: req.body && req.body.private === true, timeLabel: nowLabel(), sentAt: new Date().toISOString() });
  thread.updatedAt = Date.now();
  addFriendBoth(req.player, target);
  if (target.playerId !== req.player.playerId) {
    pushNotification(target.playerId, {
      type: "message",
      text: `${notificationPlayerName(req.player)} messaged you`,
      fromPlayerId: req.player.playerId,
      fromName: notificationPlayerName(req.player),
      threadId: thread.threadId,
      preview: body,
    });
  }
  saveState();
  res.json({ ok: true, thread: { ...threadSummary(thread, req.player), messages: thread.messages } });
});

app.get("/v1/messages/with/:playerName", requirePlayer, (req, res) => {
  const target = Object.values(state.players).find((player) => player.displayName.toLowerCase() === String(req.params.playerName || "").trim().toLowerCase());
  if (!target) return res.status(404).json({ ok: false, error: "player_not_found" });
  const thread = ensureThread(req.player, target);
  res.json({ ok: true, thread: { ...threadSummary(thread, req.player), messages: thread.messages } });
});

app.get("/v1/walls/:playerName", requirePlayer, (req, res) => {
  const key = slug(req.params.playerName);
  const target = Object.values(state.players || {}).find((player) => slug(player.displayName) === key || slug(player.name) === key);
  const posts = (state.walls[key] || []).filter((post) =>
    post.private !== true ||
    post.fromPlayerId === req.player.playerId ||
    (target && target.playerId === req.player.playerId)
  );
  res.json({ ok: true, posts });
});

app.post("/v1/walls/:playerName", requirePlayer, (req, res) => {
  const key = slug(req.params.playerName);
  const body = String(req.body.body || req.body.message || "").trim().slice(0, 280);
  if (!body) return res.status(400).json({ ok: false, error: "empty_message" });

  state.walls[key] = state.walls[key] || [];
  const post = {
    from: req.player.displayName,
    fromPlayerId: req.player.playerId,
    fromSkin: req.player.snapshot && req.player.snapshot.appearance ? req.player.snapshot.appearance.skinId : undefined,
    to: req.params.playerName,
    body,
    private: req.body && req.body.private === true,
    timeLabel: nowLabel(),
    sentAt: new Date().toISOString(),
  };
  state.walls[key].push(post);
  saveState();
  res.json({ ok: true, post, posts: state.walls[key] });
});

app.get("/v1/guilds/search", (req, res) => {
  const query = String(req.query.q || "").trim().toLowerCase();
  if (!query) return res.json({ ok: true, guilds: [] });
  const seen = new Set();
  const guilds = Object.values(state.guilds)
    .filter((guild) => guild.isPublic !== false)
    .filter((guild) => !query || guild.name.toLowerCase().includes(query))
    .filter((guild) => {
      const key = `${guild.leaderPlayerId || ""}:${guild.name.toLowerCase()}`;
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    })
    .map(publicGuild);
  res.json({ ok: true, guilds });
});

app.post("/v1/guilds", requirePlayer, (req, res) => {
  const name = String(req.body.name || "New Guild").trim().slice(0, 32);
  const existing = Object.values(state.guilds).find((guild) => guild.leaderPlayerId === req.player.playerId);
  if (existing) {
    if (existing.name.toLowerCase() !== name.toLowerCase()) {
      return res.status(409).json({ ok: false, error: "already_created_guild", guild: publicGuild(existing) });
    }
    existing.desc = String(req.body.desc || existing.desc || "").trim().slice(0, 240);
    existing.maxMembers = Number(req.body.maxMembers) || existing.maxMembers || 20;
    existing.isPublic = req.body.isPublic !== false;
    upsertGuildOnPlayer(req.player, existing, "Leader");
    req.player.createdGuild = { ...publicGuild(existing), role: "LEADER" };
    saveState();
    return res.json({ ok: true, guild: publicGuild(existing), members: guildMembers(existing), player: fullPlayer(req.player) });
  }
  const guildId = `guild_${slug(name)}_${Date.now().toString(36)}`;
  const guild = {
    guildId,
    name,
    leaderPlayerId: req.player.playerId,
    maxMembers: Number(req.body.maxMembers) || 20,
    isPublic: req.body.isPublic !== false,
    level: 1,
    members: [req.player.playerId],
    desc: String(req.body.desc || "").trim().slice(0, 240),
    vault: {},
    vaultItems: {},
    contributions: {},
    auctions: [],
    createdAt: new Date().toISOString(),
  };
  state.guilds[guildId] = guild;
  upsertGuildOnPlayer(req.player, guild, "Leader");
  req.player.createdGuild = { ...publicGuild(guild), role: "LEADER" };
  saveState();
  res.json({ ok: true, guild: publicGuild(guild), player: fullPlayer(req.player) });
});

app.post("/v1/guilds/:guildId/join", requirePlayer, (req, res) => {
  const guild = state.guilds[req.params.guildId];
  if (!guild) return res.status(404).json({ ok: false, error: "guild_not_found" });
  if (guild.isPublic === false) return res.status(403).json({ ok: false, error: "guild_private" });
  guild.members = Array.isArray(guild.members) ? guild.members : [];
  const joinedGuild = playerJoinedGuild(req.player, guild.guildId);
  if (joinedGuild) {
    return res.status(409).json({ ok: false, error: "leave_joined_guild_first", guild: joinedGuild });
  }
  if (guild.members.length >= (guild.maxMembers || 20) && !guild.members.includes(req.player.playerId)) {
    return res.status(409).json({ ok: false, error: "guild_full" });
  }
  if (!guild.members.includes(req.player.playerId)) guild.members.push(req.player.playerId);
  upsertGuildOnPlayer(req.player, guild, guild.leaderPlayerId === req.player.playerId ? "Leader" : "Member");
  if (guild.leaderPlayerId === req.player.playerId) {
    req.player.createdGuild = { ...publicGuild(guild), role: "LEADER" };
  } else {
    req.player.guild = { ...publicGuild(guild), role: "MEMBER" };
  }
  saveState();
  res.json({ ok: true, guild: publicGuild(guild), members: guildMembers(guild), player: fullPlayer(req.player) });
});

function updateGuildSettings(req, res) {
  let guild = state.guilds[req.params.guildId];
  if (!guild) {
    const requestedName = String((req.body && req.body.name) || "").trim().toLowerCase();
    guild = Object.values(state.guilds).find((entry) =>
      entry.leaderPlayerId === req.player.playerId &&
      (!requestedName || entry.name.toLowerCase() === requestedName)
    );
  }
  if (!guild) return res.status(404).json({ ok: false, error: "guild_not_found" });
  if (guild.leaderPlayerId !== req.player.playerId) return res.status(403).json({ ok: false, error: "leader_required" });

  const name = String((req.body && req.body.name) || guild.name || "Guild").trim().slice(0, 32);
  const desc = String((req.body && (req.body.desc ?? req.body.description)) ?? guild.desc ?? "").trim().slice(0, 240);
  if (!name) return res.status(400).json({ ok: false, error: "guild_name_required" });

  guild.name = name;
  guild.desc = desc;
  guild.members = Array.isArray(guild.members) ? guild.members : [];
  for (const memberId of guild.members) {
    const member = state.players[memberId];
    if (member) upsertGuildOnPlayer(member, guild, guild.leaderPlayerId === memberId ? "Leader" : "Member");
  }

  saveState();
  res.json({
    ok: true,
    guild: publicGuild(guild),
    members: guildMembers(guild),
    messages: visibleGuildMessages(guild, req.player.playerId),
    economy: publicGuildEconomy(guild),
    player: fullPlayer(req.player),
  });
}

app.patch("/v1/guilds/:guildId", requirePlayer, updateGuildSettings);
app.post("/v1/guilds/:guildId/update", requirePlayer, updateGuildSettings);

app.post("/v1/guilds/:guildId/leave", requirePlayer, (req, res) => {
  const guild = state.guilds[req.params.guildId];
  if (!guild) return res.status(404).json({ ok: false, error: "guild_not_found" });
  if (!isGuildMember(guild, req.player.playerId)) return res.status(403).json({ ok: false, error: "not_guild_member" });
  if (guild.leaderPlayerId === req.player.playerId) return res.status(403).json({ ok: false, error: "leader_cannot_leave" });

  guild.members = guild.members.filter((id) => id !== req.player.playerId);
  removeGuildFromPlayer(req.player, guild.guildId);
  saveState();
  res.json({ ok: true, guild: null, members: guildMembers(guild), player: fullPlayer(req.player) });
});

const MEMBER_RANKS = new Set(["MEMBER", "CAPTAIN", "LIEUTENANT", "GENERAL"]);

app.post("/v1/guilds/:guildId/members/:playerId/rank", requirePlayer, (req, res) => {
  const guild = state.guilds[req.params.guildId];
  if (!guild) return res.status(404).json({ ok: false, error: "guild_not_found" });
  if (guild.leaderPlayerId !== req.player.playerId) return res.status(403).json({ ok: false, error: "leader_required" });
  if (req.params.playerId === guild.leaderPlayerId) return res.status(409).json({ ok: false, error: "cannot_rank_leader" });
  if (!isGuildMember(guild, req.params.playerId)) return res.status(404).json({ ok: false, error: "member_not_found" });

  const rank = String((req.body && req.body.rank) || "").trim().toUpperCase();
  if (!MEMBER_RANKS.has(rank)) return res.status(400).json({ ok: false, error: "invalid_rank" });

  guild.memberRanks = guild.memberRanks || {};
  guild.memberRanks[req.params.playerId] = rank;
  const member = state.players[req.params.playerId];
  if (member) upsertGuildOnPlayer(member, guild, rank);
  saveState();
  res.json({ ok: true, guild: publicGuild(guild), members: guildMembers(guild), player: fullPlayer(req.player) });
});

app.post("/v1/guilds/:guildId/members/:playerId/kick", requirePlayer, (req, res) => {
  const guild = state.guilds[req.params.guildId];
  if (!guild) return res.status(404).json({ ok: false, error: "guild_not_found" });
  if (guild.leaderPlayerId !== req.player.playerId) return res.status(403).json({ ok: false, error: "leader_required" });
  if (req.params.playerId === guild.leaderPlayerId) return res.status(409).json({ ok: false, error: "cannot_kick_leader" });
  if (!isGuildMember(guild, req.params.playerId)) return res.status(404).json({ ok: false, error: "member_not_found" });

  guild.members = guild.members.filter((id) => id !== req.params.playerId);
  guild.memberRanks = guild.memberRanks || {};
  delete guild.memberRanks[req.params.playerId];
  const member = state.players[req.params.playerId];
  if (member) removeGuildFromPlayer(member, guild.guildId);
  saveState();
  res.json({ ok: true, guild: publicGuild(guild), members: guildMembers(guild), player: fullPlayer(req.player) });
});

app.get("/v1/guilds/:guildId/wars", requirePlayer, (req, res) => {
  const guild = state.guilds[req.params.guildId];
  if (!guild) return res.status(404).json({ ok: false, error: "guild_not_found" });
  if (!isGuildMember(guild, req.player.playerId)) return res.status(403).json({ ok: false, error: "not_guild_member" });
  if (materializeReadyGuildWars()) saveState();

  const wars = [];
  const seenWarIds = new Set();
  for (const entry of Object.values(state.guilds || {})) {
    for (const war of ensureGuildWars(entry)) {
      if (war.attackerGuildId === guild.guildId || war.defenderGuildId === guild.guildId) {
        if ((war.status || "active") !== "active") continue;
        if (seenWarIds.has(war.warId)) continue;
        seenWarIds.add(war.warId);
        wars.push(publicGuildWar(war));
      }
    }
  }
  wars.sort((a, b) => Date.parse(b.createdAt || 0) - Date.parse(a.createdAt || 0));
  res.json({ ok: true, guild: publicGuild(guild), wars });
});

app.post("/v1/guilds/:guildId/wars", requirePlayer, (req, res) => {
  const attacker = state.guilds[req.params.guildId];
  if (!attacker) return res.status(404).json({ ok: false, error: "guild_not_found" });
  if (!isGuildMember(attacker, req.player.playerId)) return res.status(403).json({ ok: false, error: "not_guild_member" });
  if (attacker.leaderPlayerId !== req.player.playerId) return res.status(403).json({ ok: false, error: "leader_required" });

  const body = req.body || {};
  const targetGuildId = String(body.targetGuildId || body.defenderGuildId || "").trim();
  const targetName = String(body.targetName || body.name || "").trim().toLowerCase();
  const defender = state.guilds[targetGuildId] ||
    Object.values(state.guilds || {}).find((guild) => guild.name && guild.name.toLowerCase() === targetName);
  if (!defender) return res.status(404).json({ ok: false, error: "target_guild_not_found" });
  if (defender.guildId === attacker.guildId) return res.status(409).json({ ok: false, error: "cannot_war_self" });
  const existingPending = ensureGuildWars(attacker).find((war) =>
    (war.status || "active") === "pending" &&
    war.attackerGuildId === attacker.guildId &&
    war.defenderGuildId === defender.guildId &&
    Date.parse(war.readyAt || "") > Date.now()
  );
  if (existingPending) {
    return res.status(409).json({ ok: false, error: "war_pending", war: publicGuildWar(existingPending) });
  }

  const createdAt = new Date().toISOString();
  const readyAt = new Date(Date.now() + GUILD_WAR_PREP_MS).toISOString();
  const warId = `war_${attacker.guildId}_${defender.guildId}_${Date.now().toString(36)}`;
  const attackers = pickGuildWarTeam(attacker, "player", `${warId}:attackers`);
  const defenders = pickGuildWarTeam(defender, "enemy", `${warId}:defenders`);
  const war = {
    warId,
    createdAt,
    readyAt,
    status: "pending",
    attackerGuildId: attacker.guildId,
    attackerGuildName: attacker.name,
    defenderGuildId: defender.guildId,
    defenderGuildName: defender.name,
    attackers,
    defenders,
  };

  ensureGuildWars(attacker).push(war);
  ensureGuildWars(defender).push(war);
  saveState();
  res.json({ ok: true, guild: publicGuild(attacker), war: publicGuildWar(war), wars: ensureGuildWars(attacker).filter((entry) => (entry.status || "active") === "active").map(publicGuildWar) });
});

app.post("/v1/guilds/:guildId/loot/prepare", requirePlayer, (req, res) => {
  const guild = state.guilds[req.params.guildId];
  if (!guild) return res.status(404).json({ ok: false, error: "guild_not_found" });
  if (isGuildMember(guild, req.player.playerId)) {
    return res.status(403).json({ ok: false, error: "cannot_loot_own_guild" });
  }
  const activeJail = activeGuildJailForPlayer(req.player.playerId);
  if (activeJail) {
    return res.status(423).json({
      ok: false,
      error: "guild_jail_active",
      guildId: activeJail.guild.guildId,
      guildName: activeJail.guild.name,
      releaseAt: activeJail.entry.releaseAt,
    });
  }

  const playerLevel = Math.max(1, Number((req.player.snapshot && req.player.snapshot.level) || req.player.level || 1) || 1);
  const guildLevel = guildAverageLevel(guild);
  if (Math.abs(guildLevel - playerLevel) > 3) {
    return res.status(409).json({
      ok: false,
      error: "guild_level_out_of_range",
      playerLevel,
      guildLevel,
      minLevel: playerLevel - 3,
      maxLevel: playerLevel + 3,
    });
  }

  guild.members = Array.isArray(guild.members) ? guild.members : [];
  const seed = `guild-loot:${guild.guildId}:${req.player.playerId}:${Date.now()}`;
  const rand = createSeededRandom(seed);
  const pool = guild.members
    .map((id) => state.players[id])
    .filter(Boolean)
    .filter((player) => player.playerId !== req.player.playerId);
  const picked = pickManyUnique(rand, pool, 5);
  const defenders = picked.map((player, index) => {
    const defender = lootDefenderSnapshot(player, index);
    defender.pets = [];
    defender.equipped = { ...(defender.equipped || {}), pets: [] };
    return defender;
  });

  const guildTeamHp = defenders.reduce((sum, defender) => sum + (Number(defender.hp) || 0), 0);
  res.json({
    ok: true,
    guild: publicGuild(guild),
    guildLevel,
    playerLevel,
    guildTeamHp,
    defenderCount: defenders.length,
    guildMemberCount: guild.members.length,
    defenders,
  });
});

app.post("/v1/guilds/:guildId/loot/report", requirePlayer, (req, res) => {
  const guild = state.guilds[req.params.guildId];
  if (!guild) return res.status(404).json({ ok: false, error: "guild_not_found" });
  if (isGuildMember(guild, req.player.playerId)) {
    return res.status(403).json({ ok: false, error: "cannot_loot_own_guild" });
  }

  const won = req.body && req.body.won === true;
  if (won) {
    const reward = rollGuildLootReward(req.player, guild);
    saveState();
    return res.json({
      ok: true,
      won: true,
      reward,
      guild: publicGuild(guild),
      jail: publicGuildJail(guild),
      player: fullPlayer(req.player),
    });
  }

  const jailEntry = jailPlayerInGuild(guild, req.player);
  addAuditLog({
    player: req.player,
    action: "guild_loot_failed_jail",
    before: null,
    after: jailEntry,
    reason: "Guild loot defeat",
    source: "guild_loot",
    meta: { guildId: guild.guildId, guildName: guild.name },
  });
  saveState();
  res.json({
    ok: true,
    won: false,
    jailEntry,
    guild: publicGuild(guild),
    jail: publicGuildJail(guild),
    player: fullPlayer(req.player),
  });
});

app.get("/v1/guilds/:guildId/jail", requirePlayer, (req, res) => {
  const guild = state.guilds[req.params.guildId];
  if (!guild) return res.status(404).json({ ok: false, error: "guild_not_found" });
  res.json({ ok: true, guild: publicGuild(guild), jail: publicGuildJail(guild) });
});

app.get("/v1/guilds/:guildId/vault", requirePlayer, (req, res) => {
  const guild = state.guilds[req.params.guildId];
  if (!guild) return res.status(404).json({ ok: false, error: "guild_not_found" });
  if (!isGuildMember(guild, req.player.playerId)) return res.status(403).json({ ok: false, error: "not_guild_member" });
  res.json({ ok: true, economy: publicGuildEconomy(guild) });
});

app.post("/v1/guilds/:guildId/vault/donate", requirePlayer, (req, res) => {
  const guild = state.guilds[req.params.guildId];
  if (!guild) return res.status(404).json({ ok: false, error: "guild_not_found" });
  if (!isGuildMember(guild, req.player.playerId)) return res.status(403).json({ ok: false, error: "not_guild_member" });

  const body = req.body || {};
  const key = String(body.key || body.itemId || "").trim().slice(0, 80);
  const qty = Math.max(1, Math.min(999999, Math.floor(Number(body.qty || body.amount || 1))));
  if (!key) return res.status(400).json({ ok: false, error: "item_key_required" });

  const item = {
    key,
    name: String(body.name || body.item && body.item.name || key).slice(0, 80),
    sprite: String(body.sprite || body.icon || body.item && (body.item.sprite || body.item.icon) || "").slice(0, 180),
    color: body.color || body.item && body.item.color || null,
    type: String(body.type || body.item && body.item.type || "").slice(0, 40),
  };
  const before = {
    playerGold: Number(req.player.gold) || 0,
    playerMaterialQty: req.player.materials ? Number(req.player.materials[key]) || 0 : 0,
    playerInventoryCount: Array.isArray(req.player.inventory) ? req.player.inventory.filter((entry) => entry === key).length : 0,
    guildVaultQty: ensureGuildEconomy(guild).vault[key] || 0,
  };

  if (!removePlayerItemForDonation(req.player, item, qty)) {
    return res.status(409).json({ ok: false, error: "not_enough_items" });
  }

  addItemToGuildVault(guild, item, qty);
  addGuildContribution(guild, req.player, item, qty);
  addAuditLog({
    player: req.player,
    action: "vault_deposit",
    before,
    after: {
      playerGold: Number(req.player.gold) || 0,
      playerMaterialQty: req.player.materials ? Number(req.player.materials[key]) || 0 : 0,
      playerInventoryCount: Array.isArray(req.player.inventory) ? req.player.inventory.filter((entry) => entry === key).length : 0,
      guildVaultQty: ensureGuildEconomy(guild).vault[key] || 0,
    },
    reason: "Player donated item to guild vault",
    source: "guild_vault",
    meta: { guildId: guild.guildId, guildName: guild.name, key, qty, item },
  });
  saveState();
  res.json({ ok: true, economy: publicGuildEconomy(guild), player: fullPlayer(req.player) });
});

app.post("/v1/guilds/:guildId/land/collect", requirePlayer, (req, res) => {
  const guild = state.guilds[req.params.guildId];
  if (!guild) return res.status(404).json({ ok: false, error: "guild_not_found" });
  if (!isGuildMember(guild, req.player.playerId)) return res.status(403).json({ ok: false, error: "not_guild_member" });
  if (guild.leaderPlayerId !== req.player.playerId) return res.status(403).json({ ok: false, error: "leader_required" });

  const body = req.body || {};
  const key = String(body.key || body.itemId || "").trim().slice(0, 80);
  const qty = Math.max(1, Math.min(999999, Math.floor(Number(body.qty || body.amount || 1))));
  if (!key) return res.status(400).json({ ok: false, error: "item_key_required" });

  const item = {
    key,
    name: String(body.name || body.item && body.item.name || key).slice(0, 80),
    sprite: String(body.sprite || body.icon || body.item && (body.item.sprite || body.item.icon) || "").slice(0, 180),
    color: body.color || body.item && body.item.color || null,
    type: String(body.type || body.item && body.item.type || "").slice(0, 40),
  };
  const before = { guildVaultQty: ensureGuildEconomy(guild).vault[key] || 0 };

  addItemToGuildVault(guild, item, qty);
  addGuildContribution(guild, req.player, item, qty);
  addAuditLog({
    player: req.player,
    action: "guild_land_collect",
    before,
    after: { guildVaultQty: ensureGuildEconomy(guild).vault[key] || 0 },
    reason: "Guild land reward collected to vault",
    source: "guild_land",
    meta: { guildId: guild.guildId, guildName: guild.name, key, qty, item },
  });
  saveState();
  res.json({ ok: true, economy: publicGuildEconomy(guild), player: fullPlayer(req.player) });
});

app.post("/v1/guilds/:guildId/vault/take", requirePlayer, (req, res) => {
  const guild = state.guilds[req.params.guildId];
  if (!guild) return res.status(404).json({ ok: false, error: "guild_not_found" });
  if (!isGuildMember(guild, req.player.playerId)) return res.status(403).json({ ok: false, error: "not_guild_member" });

  const key = String((req.body && (req.body.key || req.body.itemId)) || "").trim().slice(0, 80);
  const qty = Math.max(1, Math.min(99, Math.floor(Number((req.body && (req.body.qty || req.body.amount)) || 1))));
  if (!key) return res.status(400).json({ ok: false, error: "item_key_required" });
  const before = {
    guildVaultQty: ensureGuildEconomy(guild).vault[key] || 0,
    playerGold: Number(req.player.gold) || 0,
    playerMaterialQty: req.player.materials ? Number(req.player.materials[key]) || 0 : 0,
    playerInventoryCount: Array.isArray(req.player.inventory) ? req.player.inventory.filter((entry) => entry === key).length : 0,
  };
  if (!decrementGuildVault(guild, key, qty)) {
    return res.status(409).json({ ok: false, error: "not_enough_vault_items" });
  }

  const meta = guild.vaultItems && guild.vaultItems[key] ? guild.vaultItems[key] : {};
  grantPlayerItem(req.player, { key, type: meta.type }, qty);
  addAuditLog({
    player: req.player,
    action: "vault_withdraw",
    before,
    after: {
      guildVaultQty: ensureGuildEconomy(guild).vault[key] || 0,
      playerGold: Number(req.player.gold) || 0,
      playerMaterialQty: req.player.materials ? Number(req.player.materials[key]) || 0 : 0,
      playerInventoryCount: Array.isArray(req.player.inventory) ? req.player.inventory.filter((entry) => entry === key).length : 0,
    },
    reason: "Player took item from guild vault",
    source: "guild_vault",
    meta: { guildId: guild.guildId, guildName: guild.name, key, qty },
  });

  saveState();
  res.json({ ok: true, economy: publicGuildEconomy(guild), player: fullPlayer(req.player) });
});

app.get("/v1/guilds/:guildId/contributions", requirePlayer, (req, res) => {
  const guild = state.guilds[req.params.guildId];
  if (!guild) return res.status(404).json({ ok: false, error: "guild_not_found" });
  if (!isGuildMember(guild, req.player.playerId)) return res.status(403).json({ ok: false, error: "not_guild_member" });
  res.json({ ok: true, contributions: publicGuildEconomy(guild).contributions });
});

app.get("/v1/guilds/:guildId/auctions", requirePlayer, (req, res) => {
  const guild = state.guilds[req.params.guildId];
  if (!guild) return res.status(404).json({ ok: false, error: "guild_not_found" });
  if (!isGuildMember(guild, req.player.playerId)) return res.status(403).json({ ok: false, error: "not_guild_member" });
  res.json({ ok: true, auctions: publicGuildEconomy(guild).auctions });
});

app.post("/v1/guilds/:guildId/auctions", requirePlayer, (req, res) => {
  const guild = state.guilds[req.params.guildId];
  if (!guild) return res.status(404).json({ ok: false, error: "guild_not_found" });
  if (!isGuildMember(guild, req.player.playerId)) return res.status(403).json({ ok: false, error: "not_guild_member" });
  if (guild.leaderPlayerId !== req.player.playerId) return res.status(403).json({ ok: false, error: "leader_required" });

  const body = req.body || {};
  const key = String(body.key || body.itemId || "").trim().slice(0, 80);
  if (!key) return res.status(400).json({ ok: false, error: "item_key_required" });

  const qty = Math.max(1, Math.min(99, Math.floor(Number(body.qty || 1))));
  const before = { guildVaultQty: ensureGuildEconomy(guild).vault[key] || 0 };
  if (!decrementGuildVault(guild, key, qty)) {
    return res.status(409).json({ ok: false, error: "not_enough_vault_items" });
  }

  ensureGuildEconomy(guild);
  const savedItem = guild.vaultItems[key] || {};
  const requestedPrice = Math.max(1, Math.floor(Number(body.price || body.startingBid || 1)));
  const auctionFloor = Math.max(1, Math.floor(Number(body.auctionPrice || body.minPrice || body.floorPrice || savedItem.auctionPrice || 1)));
  const auctionPrice = Math.max(requestedPrice, auctionFloor);
  const auction = {
    auctionId: `auction_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 8)}`,
    key,
    qty,
    name: String(body.name || savedItem.name || key).slice(0, 80),
    sprite: String(body.sprite || savedItem.sprite || "").slice(0, 180),
    color: body.color || savedItem.color || null,
    type: String(body.type || savedItem.type || "").slice(0, 40),
    price: auctionPrice,
    auctionPrice: auctionFloor,
    minRank: String(body.minRank || "MEMBER").toUpperCase().slice(0, 20),
    seller: req.player.displayName || "Player",
    sellerPlayerId: req.player.playerId,
    bids: [],
    status: "open",
    createdAt: new Date().toISOString(),
  };
  guild.auctions.push(auction);
  addAuditLog({
    player: req.player,
    action: "auction_create",
    before,
    after: { guildVaultQty: ensureGuildEconomy(guild).vault[key] || 0, auction },
    reason: "Leader moved vault item into guild auction",
    source: "guild_auction",
    meta: { guildId: guild.guildId, guildName: guild.name, key, qty, auctionId: auction.auctionId },
  });
  saveState();
  res.json({ ok: true, auction, economy: publicGuildEconomy(guild) });
});

app.post("/v1/guilds/:guildId/auctions/:auctionId/bid", requirePlayer, (req, res) => {
  const guild = state.guilds[req.params.guildId];
  if (!guild) return res.status(404).json({ ok: false, error: "guild_not_found" });
  if (!isGuildMember(guild, req.player.playerId)) return res.status(403).json({ ok: false, error: "not_guild_member" });
  ensureGuildEconomy(guild);

  const auction = guild.auctions.find((entry) => entry.auctionId === req.params.auctionId);
  if (!auction || auction.status !== "open") return res.status(404).json({ ok: false, error: "auction_not_found" });

  const amount = Math.max(1, Math.floor(Number(req.body && (req.body.amount || req.body.bid) || 0)));
  if (amount <= (auction.price || 0)) return res.status(400).json({ ok: false, error: "bid_too_low" });
  if ((req.player.gold || 0) < amount) return res.status(409).json({ ok: false, error: "not_enough_gold" });
  if (auction.sellerPlayerId === req.player.playerId) return res.status(409).json({ ok: false, error: "cannot_buy_own_auction" });

  auction.price = amount;
  auction.bids = auction.bids || [];
  auction.bids.push({
    playerId: req.player.playerId,
    name: req.player.displayName || "Player",
    amount,
    createdAt: new Date().toISOString(),
  });
  auction.status = "sold";
  auction.buyerPlayerId = req.player.playerId;
  auction.buyer = req.player.displayName || "Player";
  auction.soldAt = new Date().toISOString();

  const seller = auction.sellerPlayerId && state.players[auction.sellerPlayerId];
  const before = {
    buyerGold: Number(req.player.gold) || 0,
    sellerGold: seller ? Number(seller.gold) || 0 : null,
    buyerMaterialQty: req.player.materials ? Number(req.player.materials[auction.key]) || 0 : 0,
    buyerInventoryCount: Array.isArray(req.player.inventory) ? req.player.inventory.filter((entry) => entry === auction.key).length : 0,
  };
  req.player.gold = (Number(req.player.gold) || 0) - amount;
  grantPlayerItem(req.player, auction, auction.qty || 1);

  if (seller) {
    seller.gold = (Number(seller.gold) || 0) + amount;
  }
  guild.auctions = guild.auctions.filter((entry) => entry.auctionId !== auction.auctionId);
  addAuditLog({
    player: req.player,
    action: "item_purchase",
    before,
    after: {
      buyerGold: Number(req.player.gold) || 0,
      sellerGold: seller ? Number(seller.gold) || 0 : null,
      buyerMaterialQty: req.player.materials ? Number(req.player.materials[auction.key]) || 0 : 0,
      buyerInventoryCount: Array.isArray(req.player.inventory) ? req.player.inventory.filter((entry) => entry === auction.key).length : 0,
    },
    reason: "Guild auction purchase",
    source: "guild_auction",
    meta: { guildId: guild.guildId, guildName: guild.name, auctionId: auction.auctionId, key: auction.key, qty: auction.qty || 1, amount },
  });
  saveState();
  res.json({ ok: true, auction, auctions: guild.auctions, economy: publicGuildEconomy(guild), player: fullPlayer(req.player) });
});

app.get("/v1/guilds/:guildId", requirePlayer, (req, res) => {
  const guild = state.guilds[req.params.guildId];
  if (!guild) return res.status(404).json({ ok: false, error: "guild_not_found" });
  if (materializeReadyGuildWars()) saveState();
  res.json({
    ok: true,
    guild: publicGuild(guild),
    members: guildMembers(guild),
    messages: state.guildChats[guild.guildId] || [],
    jail: publicGuildJail(guild),
    economy: publicGuildEconomy(guild),
    pendingWar: pendingWarForViewerGuild(guild, req.player),
  });
});

app.get("/v1/guilds/:guildId/chat", requirePlayer, (req, res) => {
  const guild = state.guilds[req.params.guildId];
  if (!guild) return res.status(404).json({ ok: false, error: "guild_not_found" });
  res.json({ ok: true, messages: visibleGuildMessages(guild, req.player.playerId) });
});

app.post("/v1/guilds/:guildId/chat", requirePlayer, (req, res) => {
  const guild = state.guilds[req.params.guildId];
  if (!guild) return res.status(404).json({ ok: false, error: "guild_not_found" });
  const privateMessage = req.body && req.body.private === true;
  if (privateMessage && !isGuildMember(guild, req.player.playerId)) return res.status(403).json({ ok: false, error: "not_guild_member" });

  const body = String((req.body && req.body.body) || "").trim().slice(0, 240);
  if (!body) return res.status(400).json({ ok: false, error: "empty_message" });

  state.guildChats[guild.guildId] = state.guildChats[guild.guildId] || [];
  const message = {
    id: `gmsg_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 8)}`,
    author: req.player.displayName || "Player",
    authorPlayerId: req.player.playerId,
    body,
    private: privateMessage,
    timeLabel: timestampLabel(),
    sentAt: new Date().toISOString(),
  };
  state.guildChats[guild.guildId].push(message);
  state.guildChats[guild.guildId] = state.guildChats[guild.guildId].slice(-100);
  saveState();
  res.json({ ok: true, message, messages: visibleGuildMessages(guild, req.player.playerId) });
});

app.delete("/v1/guilds/:guildId/chat/:messageId", requirePlayer, (req, res) => {
  const guild = state.guilds[req.params.guildId];
  if (!guild) return res.status(404).json({ ok: false, error: "guild_not_found" });
  if (!isGuildMember(guild, req.player.playerId)) return res.status(403).json({ ok: false, error: "not_guild_member" });

  const messages = state.guildChats[guild.guildId] || [];
  const index = messages.findIndex((message) => message.id === req.params.messageId);
  if (index < 0) return res.status(404).json({ ok: false, error: "message_not_found" });

  const message = messages[index];
  const canDelete = message.authorPlayerId === req.player.playerId || guild.leaderPlayerId === req.player.playerId;
  if (!canDelete) return res.status(403).json({ ok: false, error: "delete_not_allowed" });

  messages.splice(index, 1);
  state.guildChats[guild.guildId] = messages;
  saveState();
  res.json({ ok: true, messages });
});

app.post("/v1/pvp/find", requirePlayer, (req, res) => {
  const difficultyOffsets = { extreme: 2, hard: 1, casual: 0, normal: 0, easy: -1, bully: -2 };
  const difficulty = String((req.body && req.body.difficulty) || "casual").toLowerCase();
  const targetLevel = Math.max(1, Math.floor(Number((req.body && req.body.targetLevel) || ((req.player.level || 1) + (difficultyOffsets[difficulty] ?? 0)))));
  const count = Math.max(1, Math.min(8, Math.floor(Number((req.body && req.body.count) || 1))));
  const candidates = Object.values(state.players).filter((player) => {
    const level = (player.snapshot && player.snapshot.level) || player.level || 1;
    return player.playerId !== req.player.playerId && level === targetLevel;
  });
  const shuffled = candidates.sort(() => Math.random() - 0.5).slice(0, count).map(fullPlayer);

  while (shuffled.length < count) {
    const idx = shuffled.length;
    shuffled.push(buildServerBot({
      difficulty,
      targetLevel,
      idx,
      requesterLevel: req.player.level || 1,
    }));
  }

  res.json({ ok: true, targetLevel, difficulty, opponent: shuffled[0], opponents: shuffled });
});

app.post("/v1/pvp/prepare/:playerId", requirePlayer, (req, res) => {
  const opponent = state.players[req.params.playerId];
  if (!opponent) return res.status(404).json({ ok: false, error: "player_not_found" });
  if (opponent.playerId === req.player.playerId) {
    return res.status(400).json({ ok: false, error: "cannot_fight_self" });
  }

  const mode = req.body && req.body.mode === "recruit" ? "recruit" : "fight";
  res.json({
    ok: true,
    mode,
    challenger: fullPlayer(req.player),
    opponent: fullPlayer(opponent),
  });
});

app.get("/v1/pvp/history", requirePlayer, (req, res) => {
  const serverNotifications = (state.notifications && state.notifications[req.player.playerId]) || [];
  const localNotifications = Array.isArray(req.player.notifications) ? req.player.notifications : [];
  res.json({ ok: true, history: [...serverNotifications, ...localNotifications].slice(0, 50) });
});

app.post("/v1/pvp/report", requirePlayer, (req, res) => {
  const body = req.body || {};
  const targetPlayerId = String(body.targetPlayerId || "").trim();
  const target = state.players[targetPlayerId];
  if (!target) return res.status(404).json({ ok: false, error: "target_not_found" });
  if (target.playerId === req.player.playerId) return res.status(400).json({ ok: false, error: "cannot_notify_self" });

  const mode = body.mode === "recruit" ? "recruit" : "fight";
  const result = body.result || {};
  const attackerName = notificationPlayerName(req.player);
  const targetWon = result.winner !== "player";
  const text = mode === "recruit" && result.winner === "player"
    ? `You were conquered by ${attackerName}`
    : (targetWon
      ? `${attackerName} challenged you, you beat ${attackerName}`
      : `${attackerName} challenged you, you were beat by ${attackerName}`);

  const entry = pushNotification(target.playerId, {
    type: mode === "recruit" ? "conquered" : "challenge",
    text,
    fromPlayerId: req.player.playerId,
    fromName: attackerName,
    replay: {
      winner: result.winner === "player" ? "enemy" : "player",
      log: Array.isArray(result.log) ? result.log : [],
      opponent: body.challenger || fullPlayer(req.player),
    },
  });
  saveState();
  res.json({ ok: true, notification: entry });
});

app.get("/v1/tournaments/status", requirePlayer, (req, res) => {
  ensureTournamentState(req.player);
  const counts = tournamentCounts();
  res.json({
    ok: true,
    tournaments: {
      single: { joined: req.player.tournaments.single.joined === true, count: counts.single, capacity: 64 },
      crew: { joined: req.player.tournaments.crew.joined === true, count: counts.crew, capacity: 64 },
    },
  });
});

app.post("/v1/tournaments/:mode/join", requirePlayer, (req, res) => {
  const mode = req.params.mode === "crew" ? "crew" : "single";
  const joined = req.body && req.body.joined === true;
  ensureTournamentState(req.player);
  req.player.tournaments[mode].joined = joined;
  req.player.tournaments[mode].joinedAt = joined ? new Date().toISOString() : null;
  const counts = tournamentCounts();
  saveState();
  res.json({
    ok: true,
    tournaments: {
      single: { joined: req.player.tournaments.single.joined === true, count: counts.single, capacity: 64 },
      crew: { joined: req.player.tournaments.crew.joined === true, count: counts.crew, capacity: 64 },
    },
    player: fullPlayer(req.player),
  });
});

app.get("/v1/squad", requirePlayer, (req, res) => {
  const botGold = collectBotSquadGold(req.player);
  if (botGold > 0) saveState();
  res.json({ ok: true, squad: ensureSquad(req.player), botGold, player: fullPlayer(req.player) });
});

app.post("/v1/squad/recruit", requirePlayer, (req, res) => {
  const body = req.body || {};
  const target = body.target || {};
  const targetPlayerId = String(target.playerId || body.targetPlayerId || "").trim();
  if (targetPlayerId && targetPlayerId === req.player.playerId) {
    return res.status(400).json({ ok: false, error: "cannot_recruit_self" });
  }

  const squad = ensureSquad(req.player);
  if (squad.conquered.length >= 4) return res.status(409).json({ ok: false, error: "squad_full" });

  const realTarget = targetPlayerId ? state.players[targetPlayerId] : null;
  const name = realTarget
    ? (realTarget.displayName || target.name || "Player")
    : String(target.name || body.name || "Bot").trim();
  if (!name) return res.status(400).json({ ok: false, error: "missing_target" });

  if (squad.conquered.some((member) => memberKey(member) === (targetPlayerId || name) || member.name === name)) {
    return res.json({ ok: true, squad, player: fullPlayer(req.player), alreadyRecruited: true });
  }

  const member = {
    name,
    level: Number(target.level) || (realTarget && realTarget.level) || 1,
    power: Number(target.power) || 0,
    visualId: target.visualId || (realTarget && playerSkinId(realTarget)) || "street_brawler",
    targetPlayerId: targetPlayerId || null,
    bot: !targetPlayerId,
    taxRate: clampTaxRate(target.taxRate == null ? 0.10 : target.taxRate),
    contributionGold: 0,
    conqueredAt: new Date().toISOString(),
    lastBotGoldAt: Date.now(),
  };
  squad.conquered.push(member);

  if (targetPlayerId) {
    pushNotification(targetPlayerId, {
      type: "conquered",
      text: `You were conquered by ${notificationPlayerName(req.player)}`,
      fromPlayerId: req.player.playerId,
      fromName: notificationPlayerName(req.player),
    });
  }

  saveState();
  res.json({ ok: true, squad, member, player: fullPlayer(req.player) });
});

app.post("/v1/squad/tax", requirePlayer, (req, res) => {
  const member = findSquadMember(req.player, req.body || {});
  if (!member) return res.status(404).json({ ok: false, error: "member_not_found" });
  member.taxRate = clampTaxRate(req.body.rate);
  saveState();
  res.json({ ok: true, squad: ensureSquad(req.player), player: fullPlayer(req.player) });
});

app.post("/v1/squad/liberate", requirePlayer, (req, res) => {
  let squad = ensureSquad(req.player);
  const member = findSquadMember(req.player, req.body || {});
  if (!member) return res.status(404).json({ ok: false, error: "member_not_found" });
  squad.conquered = squad.conquered.filter((item) => item !== member);
  pushNotification(req.player.playerId, {
    type: "squad_rebel",
    text: `${member.name || "A squad member"} has rebelled and is no longer part of your squad`,
    fromPlayerId: member.targetPlayerId || null,
    fromName: member.name || "Squad member",
  });
  saveState();
  res.json({ ok: true, squad, player: fullPlayer(req.player) });
});

app.post("/v1/squad/fight-reward", requirePlayer, (req, res) => {
  const goldGained = Math.max(0, Math.floor(Number(req.body && req.body.goldGained) || 0));
  const payouts = [];
  let jailTax = null;
  const activeJail = activeGuildJailForPlayer(req.player.playerId);
  if (activeJail && goldGained > 0) {
    const amount = Math.max(1, Math.floor(goldGained * 0.10));
    const before = {
      playerGold: Number(req.player.gold) || 0,
      guildGold: Number(activeJail.guild.gold) || 0,
    };
    req.player.gold = Math.max(0, (Number(req.player.gold) || 0) - amount);
    activeJail.guild.gold = (Number(activeJail.guild.gold) || 0) + amount;
    jailTax = {
      guildId: activeJail.guild.guildId,
      guildName: activeJail.guild.name,
      amount,
      releaseAt: activeJail.entry.releaseAt,
    };
    addAuditLog({
      player: req.player,
      action: "arena_gold_tax",
      before,
      after: {
        playerGold: Number(req.player.gold) || 0,
        guildGold: Number(activeJail.guild.gold) || 0,
      },
      reason: "24 hour guild jail tax",
      source: "arena_reward",
      meta: { ...jailTax, goldGained },
    });
  }
  if (goldGained > 0) {
    for (const owner of Object.values(state.players || {})) {
      if (!owner || owner.playerId === req.player.playerId) continue;
      const squad = ensureSquad(owner);
      for (const member of squad.conquered) {
        if (member.targetPlayerId !== req.player.playerId) continue;
        const amount = Math.min(4, Math.floor(goldGained * clampTaxRate(member.taxRate)));
        if (amount <= 0) continue;
        owner.gold = (Number(owner.gold) || 0) + amount;
        member.contributionGold = (Number(member.contributionGold) || 0) + amount;
        addAuditLog({
          player: req.player,
          action: "squad_tax_payout",
          before: null,
          after: { ownerGold: Number(owner.gold) || 0, contributionGold: member.contributionGold },
          reason: "Squad/conquer arena tax payout",
          source: "arena_reward",
          meta: { ownerPlayerId: owner.playerId, ownerName: owner.displayName, amount, goldGained },
        });
        payouts.push({ ownerPlayerId: owner.playerId, ownerName: owner.displayName, amount });
      }
    }
  }
  if (payouts.length > 0 || jailTax) saveState();
  res.json({ ok: true, payouts, jailTax, player: jailTax ? fullPlayer(req.player) : undefined });
});

app.get("/v1/chat/world", (req, res) => {
  res.json({ ok: true, messages: [] });
});

app.post("/v1/chat/world", (req, res) => {
  res.json({ ok: true });
});

initializeState()
  .then(() => {
    app.listen(port, host, () => {
      console.log(`Server running at http://${host}:${port}`);
    });
  })
  .catch((error) => {
    console.error("Failed to initialize server state:", error);
    process.exit(1);
  });
