'use strict';

/**
 * In-memory room / matchmaking manager for the Cyber Tavla realtime server.
 *
 * Each room holds exactly two seats ("white" and "black"). The server does
 * not run the backgammon rules engine itself (that lives in the shared Dart
 * package and runs client-side); instead each room keeps an ordered
 * authoritative EVENT LOG of everything that has happened in the current
 * match (dice rolls and moves). A (re)connecting client can rebuild the
 * exact game state locally by replaying this log on top of a fresh game
 * started with the room's `startingPlayer` - that is what makes
 * reconnection robust without porting the rules engine to JavaScript.
 *
 * Porting the shared Dart engine to run server-side (for independent move
 * validation instead of trusting the mover's client) is tracked as future
 * work - see the project README.
 */

const ROOM_CODE_LENGTH = 6;
const ROOM_CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0/O/1/I ambiguity
const STALE_ROOM_TTL_MS = 6 * 60 * 60 * 1000; // 6 hours of total inactivity

/** @type {Map<string, Room>} */
const rooms = new Map();

/**
 * @typedef {Object} Room
 * @property {string} code
 * @property {{white: string|null, black: string|null}} socketIds
 * @property {{white: string|null, black: string|null}} nicknames
 * @property {{white: boolean, black: boolean}} connected
 * @property {'white'|'black'} startingPlayer
 * @property {Array<Object>} events
 * @property {Set<'white'|'black'>} rematchRequests
 * @property {number} createdAt
 * @property {number} lastActivityAt
 */

function generateRoomCode() {
  let code;
  do {
    code = '';
    for (let i = 0; i < ROOM_CODE_LENGTH; i++) {
      code += ROOM_CODE_ALPHABET[Math.floor(Math.random() * ROOM_CODE_ALPHABET.length)];
    }
  } while (rooms.has(code));
  return code;
}

function touch(room) {
  room.lastActivityAt = Date.now();
}

/**
 * Creates a brand new room with the creator seated as white.
 * @param {string} socketId
 * @param {string} nickname
 * @returns {Room}
 */
function createRoom(socketId, nickname) {
  const code = generateRoomCode();
  const now = Date.now();

  /** @type {Room} */
  const room = {
    code,
    socketIds: { white: socketId, black: null },
    nicknames: { white: nickname || null, black: null },
    connected: { white: true, black: false },
    startingPlayer: 'white',
    events: [],
    rematchRequests: new Set(),
    createdAt: now,
    lastActivityAt: now,
  };

  rooms.set(code, room);
  return room;
}

/**
 * Finds a room by its code (case-insensitive). Returns `undefined` if it
 * doesn't exist.
 * @param {string} code
 * @returns {Room|undefined}
 */
function getRoom(code) {
  if (!code) return undefined;
  return rooms.get(String(code).trim().toUpperCase());
}

/**
 * Seats a new socket into the black seat of an existing, open room.
 * @param {string} code
 * @param {string} socketId
 * @param {string} nickname
 * @returns {{ok: true, room: Room} | {ok: false, reason: 'not_found'|'full'}}
 */
function joinRoom(code, socketId, nickname) {
  const room = getRoom(code);
  if (!room) return { ok: false, reason: 'not_found' };

  if (room.socketIds.black && room.connected.black) {
    return { ok: false, reason: 'full' };
  }

  room.socketIds.black = socketId;
  room.nicknames.black = nickname || room.nicknames.black || null;
  room.connected.black = true;
  touch(room);

  return { ok: true, room };
}

/**
 * Re-attaches a socket to an existing seat after a reconnect (the
 * client asserts which color it previously held; the server trusts this,
 * consistent with the project's "server relays, client validates" model).
 * @param {string} code
 * @param {'white'|'black'} color
 * @param {string} socketId
 * @param {string} [nickname]
 * @returns {{ok: true, room: Room} | {ok: false, reason: 'not_found'|'invalid_color'}}
 */
function reattachSeat(code, color, socketId, nickname) {
  const room = getRoom(code);
  if (!room) return { ok: false, reason: 'not_found' };
  if (color !== 'white' && color !== 'black') return { ok: false, reason: 'invalid_color' };

  room.socketIds[color] = socketId;
  room.connected[color] = true;
  if (nickname) room.nicknames[color] = nickname;
  touch(room);

  return { ok: true, room };
}

/**
 * Finds the room and seat color for a given live socket id, if any.
 * @param {string} socketId
 * @returns {{room: Room, color: 'white'|'black'}|null}
 */
function findBySocketId(socketId) {
  for (const room of rooms.values()) {
    if (room.socketIds.white === socketId) return { room, color: 'white' };
    if (room.socketIds.black === socketId) return { room, color: 'black' };
  }
  return null;
}

/**
 * Marks a seat as disconnected without evicting it from the room, so a
 * later reconnect can re-attach via {@link reattachSeat}.
 * @param {string} socketId
 * @returns {{room: Room, color: 'white'|'black'}|null}
 */
function markDisconnected(socketId) {
  const found = findBySocketId(socketId);
  if (!found) return null;
  found.room.connected[found.color] = false;
  touch(found.room);
  return found;
}

/**
 * Fully removes a seat's occupant from a room (an explicit "leave", not a
 * transient disconnect). If the room ends up with no seats occupied at
 * all, the room itself is deleted.
 * @param {string} code
 * @param {'white'|'black'} color
 */
function leaveRoom(code, color) {
  const room = getRoom(code);
  if (!room) return;

  room.socketIds[color] = null;
  room.connected[color] = false;
  room.rematchRequests.delete(color);
  touch(room);

  if (!room.socketIds.white && !room.socketIds.black) {
    rooms.delete(room.code);
  }
}

/**
 * Appends an authoritative dice-roll event to the room's log.
 * @param {Room} room
 * @param {{die1: number, die2: number}} roll
 */
function recordRoll(room, roll) {
  room.events.push({ type: 'roll', roll: { die1: roll.die1, die2: roll.die2 } });
  touch(room);
}

/**
 * Appends an authoritative move event to the room's log.
 * @param {Room} room
 * @param {Object} move Already-serialized move payload (see Move.toJson on
 *   the Dart side): { player, from, to, die, isHit }.
 */
function recordMove(room, move) {
  room.events.push({ type: 'move', move });
  touch(room);
}

/**
 * Resets a room's event log and starting player for a rematch, flipping
 * who starts by convention (loser/second-mover of the prior game starts
 * next, approximated here simply as "the other color").
 * @param {Room} room
 */
function startRematch(room) {
  room.startingPlayer = room.startingPlayer === 'white' ? 'black' : 'white';
  room.events = [];
  room.rematchRequests.clear();
  touch(room);
}

/**
 * Records that [color] wants a rematch. Returns true once BOTH sides have
 * requested one (the caller should then call {@link startRematch} and
 * broadcast confirmation).
 * @param {Room} room
 * @param {'white'|'black'} color
 * @returns {boolean}
 */
function requestRematch(room, color) {
  room.rematchRequests.add(color);
  touch(room);
  return room.rematchRequests.has('white') && room.rematchRequests.has('black');
}

/** Periodically evicts rooms that have seen no activity for a long time. */
function sweepStaleRooms() {
  const now = Date.now();
  for (const [code, room] of rooms.entries()) {
    if (now - room.lastActivityAt > STALE_ROOM_TTL_MS) {
      rooms.delete(code);
    }
  }
}

function roomCount() {
  return rooms.size;
}

/**
 * Counts rooms that are genuinely open for a second player to join right
 * now: created, with the white seat still connected, and nobody seated
 * in black yet. Deliberately excludes rooms whose creator has since
 * disconnected (kept around only for {@link reattachSeat} reconnection) —
 * those aren't really "waiting for a match", just a ghost session, and
 * counting them would make the lobby indicator overstate real activity.
 * @returns {number}
 */
function waitingRoomCount() {
  let count = 0;
  for (const room of rooms.values()) {
    if (!room.socketIds.black && room.connected.white) count++;
  }
  return count;
}

module.exports = {
  createRoom,
  getRoom,
  joinRoom,
  reattachSeat,
  findBySocketId,
  markDisconnected,
  leaveRoom,
  recordRoll,
  recordMove,
  startRematch,
  requestRematch,
  sweepStaleRooms,
  roomCount,
  waitingRoomCount,
};