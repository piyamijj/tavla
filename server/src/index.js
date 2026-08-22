'use strict';

/**
 * Cyber Tavla - realtime multiplayer server entry point.
 *
 * Responsibilities (see also handlers.js and rooms.js for the details):
 *   - Serve a minimal HTTP health-check endpoint (useful for Render /
 *     Railway health checks and for a quick manual "is it alive" check).
 *   - Run a Socket.io server implementing the Cyber Tavla realtime
 *     protocol: room creation/joining by code, authoritative dice rolls,
 *     move relay between the two players in a room, reconnection support
 *     via an authoritative per-room event log, and a rematch handshake.
 *
 * This server intentionally does NOT run the backgammon rules engine
 * itself - the shared Dart engine (app/lib/shared/) does move validation
 * client-side, and this server only relays already-validated moves plus
 * generates authoritative dice rolls and manages room/seat bookkeeping.
 * Porting the engine to run here too (for independent server-side
 * validation) is tracked as future work - see the project README.
 *
 * Local development:
 *   npm install
 *   npm start
 *   # Server listens on http://localhost:3000 by default.
 *
 * Production deployment (Render / Railway - NOT Vercel, which is
 * serverless and cannot host a persistent Socket.io connection):
 *   The platform sets process.env.PORT automatically; this server reads
 *   it below. Set the CORS_ORIGIN environment variable to the deployed
 *   Flutter Web client's origin (or leave unset to allow all origins,
 *   which is fine for a mobile-only client that doesn't rely on browser
 *   CORS at all).
 */

const http = require('http');
const express = require('express');
const cors = require('cors');
const { Server } = require('socket.io');

const rooms = require('./rooms');
const { registerHandlers } = require('./handlers');

const PORT = process.env.PORT || 3000;
const CORS_ORIGIN = process.env.CORS_ORIGIN || '*';
const STALE_ROOM_SWEEP_INTERVAL_MS = 30 * 60 * 1000; // 30 minutes

const app = express();
app.use(cors({ origin: CORS_ORIGIN }));

app.get('/', (_req, res) => {
  res.json({
    name: 'cyber-tavla-server',
    status: 'ok',
    activeRooms: rooms.roomCount(),
  });
});

app.get('/health', (_req, res) => {
  res.status(200).send('ok');
});

const httpServer = http.createServer(app);

const io = new Server(httpServer, {
  cors: {
    origin: CORS_ORIGIN,
    methods: ['GET', 'POST'],
  },
});

io.on('connection', (socket) => {
  registerHandlers(io, socket);
});

setInterval(() => {
  rooms.sweepStaleRooms();
}, STALE_ROOM_SWEEP_INTERVAL_MS).unref();

httpServer.listen(PORT, () => {
  // eslint-disable-next-line no-console
  console.log(`Cyber Tavla server dinlemede: port ${PORT}`);
});

module.exports = { app, httpServer, io };