'use strict';

/**
 * Socket.io event handlers implementing the Cyber Tavla realtime protocol.
 *
 * The server acts as a room/matchmaking manager, an authoritative dice
 * roller, and a relay for moves - it does not re-validate moves against
 * the backgammon rules itself (the shared Dart engine does that
 * client-side, and only ever sends moves it already confirmed legal).
 * Porting that engine to run server-side for independent validation is
 * tracked as future work (see the project README).
 *
 * Wire protocol (client -> server events):
 *   create_room     { nickname }
 *   join_room       { roomCode, nickname }
 *   rejoin_room     { roomCode, color, nickname }
 *   request_sync    { roomCode, color, nickname }
 *   roll_dice       { roomCode }
 *   make_move       { roomCode, move }
 *   request_rematch { roomCode }
 *   leave_room      { roomCode }
 *   enter_lobby     { nickname } — mark this socket as idle/challengeable
 *                    (sent when the app's multiplayer lobby screen opens).
 *   leave_lobby     {} — the opposite of enter_lobby (screen closed
 *                    without starting a match).
 *   challenge_player{ targetId } — directly starts a match against
 *                    another currently-idle player by socket id, instead
 *                    of the manual create/share-code/join dance. Both
 *                    players must currently be idle or this fails with a
 *                    room_error.
 *
 * Wire protocol (server -> client events):
 *   room_created        { roomCode, color }
 *   joined_room         { roomCode, color, opponentNickname }
 *   room_error          { message }
 *   opponent_joined     { nickname }
 *   opponent_left       {}
 *   opponent_disconnected {}
 *   opponent_reconnected  {}
 *   game_start          { startingPlayer }
 *   dice_rolled         { die1, die2 }
 *   move_made           { move }
 *   sync_state          { startingPlayer, events, opponentNickname, opponentConnected }
 *   rematch_requested   {}
 *   rematch_confirmed   { startingPlayer }
 *   lobby_stats         { waitingRooms } — how many rooms are currently
 *                        open and waiting for a second player. Sent once
 *                        to each socket right after it connects, and
 *                        re-broadcast to every connected socket whenever
 *                        the count changes (room created/joined/left/
 *                        disconnected/reconnected). Purely informational
 *                        for a lobby-screen indicator — it does not
 *                        affect matchmaking itself.
 *   lobby_players       { players: [{id, nickname}] } — the actual list
 *                        of other currently-idle players this socket can
 *                        challenge (self excluded). Sent to every idle
 *                        socket whenever the idle set changes.
 */

const rooms = require('./rooms');

const ERROR_MESSAGES = {
  not_found: 'Oda bulunamadı',
  full: 'Oda dolu',
  invalid_color: 'Geçersiz renk bilgisi',
  not_your_turn: 'Sıra sende değil',
  no_room: 'Önce bir odaya katılmalısın',
};

function otherColor(color) {
  return color === 'white' ? 'black' : 'white';
}

function seatSocketId(room, color) {
  return room.socketIds[color];
}

/** Broadcasts the current waiting-room count to every connected socket. */
function broadcastLobbyStats(io) {
  io.emit('lobby_stats', { waitingRooms: rooms.waitingRoomCount() });
}

/**
 * Sends each currently idle socket the up-to-date list of OTHER idle
 * players (never includes yourself). Called whenever the idle set
 * changes — entering/leaving the lobby, starting a match (manually or
 * via a challenge), or disconnecting.
 */
function broadcastLobbyPlayers(io) {
  const all = rooms.listIdlePlayers();
  for (const player of all) {
    io.to(player.id).emit('lobby_players', { players: all.filter((p) => p.id !== player.id) });
  }
}

/**
 * Registers all Cyber Tavla protocol event handlers on a freshly connected
 * socket.
 * @param {import('socket.io').Server} io
 * @param {import('socket.io').Socket} socket
 */
function registerHandlers(io, socket) {
  // Give the newly connected socket the current count right away, so a
  // freshly opened lobby screen doesn't have to wait for some other
  // player's action to see an initial number.
  socket.emit('lobby_stats', { waitingRooms: rooms.waitingRoomCount() });

  socket.on('create_room', (payload) => {
    const nickname = sanitizeNickname(payload && payload.nickname);
    const room = rooms.createRoom(socket.id, nickname);
    socket.join(room.code);

    // No longer idle/challengeable now that they're setting up a room of
    // their own via the manual code-sharing flow.
    if (rooms.isIdle(socket.id)) {
      rooms.leaveLobby(socket.id);
      broadcastLobbyPlayers(io);
    }

    socket.emit('room_created', { roomCode: room.code, color: 'white' });
    broadcastLobbyStats(io);
  });

  socket.on('join_room', (payload) => {
    const roomCode = payload && payload.roomCode;
    const nickname = sanitizeNickname(payload && payload.nickname);

    const result = rooms.joinRoom(roomCode, socket.id, nickname);
    if (!result.ok) {
      socket.emit('room_error', { message: ERROR_MESSAGES[result.reason] || 'Odaya katılınamadı' });
      return;
    }

    const { room } = result;
    socket.join(room.code);

    if (rooms.isIdle(socket.id)) {
      rooms.leaveLobby(socket.id);
      broadcastLobbyPlayers(io);
    }

    socket.emit('joined_room', {
      roomCode: room.code,
      color: 'black',
      opponentNickname: room.nicknames.white,
    });

    io.to(seatSocketId(room, 'white')).emit('opponent_joined', { nickname: room.nicknames.black });

    // Both seats are now filled: the match can begin.
    io.to(room.code).emit('game_start', { startingPlayer: room.startingPlayer });
    broadcastLobbyStats(io);
  });

  socket.on('enter_lobby', (payload) => {
    const nickname = sanitizeNickname(payload && payload.nickname) || 'Oyuncu';
    rooms.enterLobby(socket.id, nickname);
    broadcastLobbyPlayers(io);
  });

  socket.on('leave_lobby', () => {
    if (!rooms.isIdle(socket.id)) return;
    rooms.leaveLobby(socket.id);
    broadcastLobbyPlayers(io);
  });

  socket.on('challenge_player', (payload) => {
    const targetId = payload && payload.targetId;
    const targetSocket = targetId ? io.sockets.sockets.get(targetId) : null;

    if (!targetId || !targetSocket || !rooms.isIdle(socket.id) || !rooms.isIdle(targetId)) {
      socket.emit('room_error', { message: 'Bu oyuncu artık uygun değil' });
      return;
    }

    const challengerNickname = rooms.idleNickname(socket.id);
    const targetNickname = rooms.idleNickname(targetId);

    rooms.leaveLobby(socket.id);
    rooms.leaveLobby(targetId);

    const room = rooms.createRoom(socket.id, challengerNickname);
    rooms.joinRoom(room.code, targetId, targetNickname);

    socket.join(room.code);
    targetSocket.join(room.code);

    socket.emit('room_created', { roomCode: room.code, color: 'white' });
    targetSocket.emit('joined_room', {
      roomCode: room.code,
      color: 'black',
      opponentNickname: challengerNickname,
    });
    socket.emit('opponent_joined', { nickname: targetNickname });
    io.to(room.code).emit('game_start', { startingPlayer: room.startingPlayer });

    broadcastLobbyPlayers(io);
    broadcastLobbyStats(io);
  });

  socket.on('rejoin_room', (payload) => {
    handleReattach(io, socket, payload);
  });

  socket.on('request_sync', (payload) => {
    // A request_sync may arrive either as a first reconnection message
    // (before the seat has been re-attached to this new socket id) or
    // after. Reattach defensively either way, then always answer with a
    // full sync_state.
    const attached = handleReattach(io, socket, payload, { silent: true });
    const roomCode = payload && payload.roomCode;
    const room = rooms.getRoom(roomCode);
    if (!room) {
      socket.emit('room_error', { message: ERROR_MESSAGES.not_found });
      return;
    }

    const color = (attached && attached.color) || resolveColorForSocket(room, socket.id);
    if (!color) {
      socket.emit('room_error', { message: ERROR_MESSAGES.invalid_color });
      return;
    }

    sendSyncState(socket, room, color);
  });

  socket.on('roll_dice', (payload) => {
    const found = rooms.findBySocketId(socket.id);
    if (!found) {
      socket.emit('room_error', { message: ERROR_MESSAGES.no_room });
      return;
    }
    const { room, color } = found;

    if (!isPlayersTurnToRoll(room, color)) {
      socket.emit('room_error', { message: ERROR_MESSAGES.not_your_turn });
      return;
    }

    const roll = { die1: rollDie(), die2: rollDie() };
    rooms.recordRoll(room, roll);

    io.to(room.code).emit('dice_rolled', roll);
  });

  socket.on('make_move', (payload) => {
    const found = rooms.findBySocketId(socket.id);
    if (!found) {
      socket.emit('room_error', { message: ERROR_MESSAGES.no_room });
      return;
    }
    const { room, color } = found;
    const move = payload && payload.move;
    if (!move || move.player !== color) {
      socket.emit('room_error', { message: ERROR_MESSAGES.not_your_turn });
      return;
    }

    rooms.recordMove(room, move);

    // Relay to the opponent only - the mover already applied it locally.
    socket.to(room.code).emit('move_made', { move });
  });

  socket.on('request_rematch', (payload) => {
    const found = rooms.findBySocketId(socket.id);
    if (!found) return;
    const { room, color } = found;

    socket.to(room.code).emit('rematch_requested', {});

    const bothRequested = rooms.requestRematch(room, color);
    if (bothRequested) {
      rooms.startRematch(room);
      io.to(room.code).emit('rematch_confirmed', { startingPlayer: room.startingPlayer });
    }
  });

  socket.on('leave_room', (payload) => {
    const roomCode = payload && payload.roomCode;
    const found = rooms.findBySocketId(socket.id);
    if (!found) return;
    const { room, color } = found;
    if (roomCode && room.code !== String(roomCode).trim().toUpperCase()) return;

    socket.leave(room.code);
    rooms.leaveRoom(room.code, color);
    socket.to(room.code).emit('opponent_left', {});
    broadcastLobbyStats(io);
  });

  socket.on('disconnect', () => {
    if (rooms.isIdle(socket.id)) {
      rooms.leaveLobby(socket.id);
      broadcastLobbyPlayers(io);
    }

    const found = rooms.markDisconnected(socket.id);
    if (!found) return;
    const { room } = found;
    socket.to(room.code).emit('opponent_disconnected', {});
    // A disconnect can turn a "waiting" room into a ghost (creator gone,
    // nobody to join) or vice versa isn't possible here, but it can
    // change the count either way depending on which seat/state this
    // was, so just recompute and broadcast rather than special-case it.
    broadcastLobbyStats(io);
  });
}

/**
 * Shared reattachment logic used by both `rejoin_room` and `request_sync`
 * (a client may call either depending on exactly when it detects it needs
 * to resync after a transport reconnect).
 */
function handleReattach(io, socket, payload, options) {
  const silent = Boolean(options && options.silent);
  const roomCode = payload && payload.roomCode;
  const color = payload && payload.color;
  const nickname = sanitizeNickname(payload && payload.nickname);

  if (!roomCode || !color) return null;

  const result = rooms.reattachSeat(roomCode, color, socket.id, nickname);
  if (!result.ok) {
    if (!silent) {
      socket.emit('room_error', { message: ERROR_MESSAGES[result.reason] || 'Yeniden bağlanılamadı' });
    }
    return null;
  }

  const { room } = result;
  socket.join(room.code);
  socket.to(room.code).emit('opponent_reconnected', {});
  // A reattach can bring a room back from "ghost" (creator was
  // disconnected) to genuinely "waiting" again if the other seat is
  // still empty, so the count needs recomputing here too.
  broadcastLobbyStats(io);

  return { room, color };
}

function resolveColorForSocket(room, socketId) {
  if (room.socketIds.white === socketId) return 'white';
  if (room.socketIds.black === socketId) return 'black';
  return null;
}

function sendSyncState(socket, room, color) {
  const opponent = otherColor(color);
  socket.emit('sync_state', {
    startingPlayer: room.startingPlayer,
    events: room.events,
    opponentNickname: room.nicknames[opponent],
    opponentConnected: Boolean(room.connected[opponent]),
  });
}

/**
 * Whose turn it is to roll, derived from a simple invariant that holds
 * regardless of how many moves were played (or skipped, when a player
 * "dances" with no legal move) in each turn: every player turn consumes
 * exactly one roll event, so roll events strictly alternate starting from
 * `room.startingPlayer`. Counting them tells us whose roll should come
 * next without needing to replay the engine's full turn-advancement logic
 * (dice usage, forced bar entry, etc.) server-side - that logic stays
 * solely in the shared Dart engine, per the module docstring.
 */
function isPlayersTurnToRoll(room, color) {
  const rollCount = room.events.filter((event) => event.type === 'roll').length;
  const expectedColor = rollCount % 2 === 0 ? room.startingPlayer : otherColor(room.startingPlayer);
  return color === expectedColor;
}

function rollDie() {
  return 1 + Math.floor(Math.random() * 6);
}

function sanitizeNickname(nickname) {
  if (typeof nickname !== 'string') return null;
  const trimmed = nickname.trim().slice(0, 24);
  return trimmed.length > 0 ? trimmed : null;
}

module.exports = { registerHandlers };