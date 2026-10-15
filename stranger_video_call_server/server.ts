import http from "node:http";
import { Server } from "socket.io";

const PORT = Number(process.env.PORT) || 3000;

const httpServer = http.createServer((req, res) => {
  // Health check
  if (req.url === "/health") {
    res.writeHead(200, {
      "Content-Type": "application/json",
    });

    res.end(
      JSON.stringify({
        status: "ok",
        service: "stranger-video-call-signaling",
        timestamp: new Date().toISOString(),
      }),
    );

    return;
  }

  res.writeHead(200, {
    "Content-Type": "text/plain",
  });

  res.end("Stranger Video Call Signaling Server");
});

const io = new Server(httpServer, {
  cors: {
    origin: "*",
    methods: ["GET", "POST"],
  },

  transports: ["websocket", "polling"],
});

// ============================================================
// CONNECTION
// ============================================================

io.on("connection", (socket) => {
  console.log("Connected:", socket.id);

  // ==========================================================
  // JOIN ROOM
  // ==========================================================

  socket.on(
    "join-room",
    async (
      roomId: string,
      callback?: (response: {
        success: boolean;
        message?: string;
        roomId?: string;
        participantCount?: number;
      }) => void,
    ) => {
      try {
        if (!roomId || typeof roomId !== "string") {
          callback?.({
            success: false,
            message: "Invalid room ID",
          });

          return;
        }

        const normalizedRoomId = roomId
          .trim()
          .toUpperCase();

        const room =
          io.sockets.adapter.rooms.get(
            normalizedRoomId,
          );

        const participantCount = room
          ? room.size
          : 0;

        // Maximum 2 people
        if (participantCount >= 2) {
          callback?.({
            success: false,
            message: "Room is full",
          });

          return;
        }

        await socket.join(normalizedRoomId);

        socket.data.roomId = normalizedRoomId;

        const updatedRoom =
          io.sockets.adapter.rooms.get(
            normalizedRoomId,
          );

        const count = updatedRoom
          ? updatedRoom.size
          : 0;

        console.log(
          `Socket ${socket.id} joined ${normalizedRoomId} (${count}/2)`,
        );

        callback?.({
          success: true,
          roomId: normalizedRoomId,
          participantCount: count,
        });

        // Notify first participant
        if (count === 2) {
          socket
            .to(normalizedRoomId)
            .emit("peer-joined");
        }
      } catch (error) {
        console.error(
          "Join room error:",
          error,
        );

        callback?.({
          success: false,
          message: "Unable to join room",
        });
      }
    },
  );

  // ==========================================================
  // WEBRTC OFFER
  // ==========================================================

  socket.on("offer", (data) => {
    const roomId = socket.data.roomId;

    if (!roomId) {
      return;
    }

    socket
      .to(roomId)
      .emit("offer", data);
  });

  // ==========================================================
  // WEBRTC ANSWER
  // ==========================================================

  socket.on("answer", (data) => {
    const roomId = socket.data.roomId;

    if (!roomId) {
      return;
    }

    socket
      .to(roomId)
      .emit("answer", data);
  });

  // ==========================================================
  // ICE CANDIDATE
  // ==========================================================

  socket.on(
    "ice-candidate",
    (data) => {
      const roomId = socket.data.roomId;

      if (!roomId) {
        return;
      }

      socket
        .to(roomId)
        .emit(
          "ice-candidate",
          data,
        );
    },
  );

  // ==========================================================
  // LEAVE ROOM
  // ==========================================================

  socket.on(
    "leave-room",
    async () => {
      await leaveRoom(socket);
    },
  );

  // ==========================================================
  // DISCONNECT
  // ==========================================================

  socket.on(
    "disconnect",
    async () => {
      console.log(
        "Disconnected:",
        socket.id,
      );

      await leaveRoom(socket);
    },
  );
});

// ============================================================
// LEAVE ROOM FUNCTION
// ============================================================

async function leaveRoom(
  socket: any,
) {
  const roomId =
    socket.data.roomId;

  if (!roomId) {
    return;
  }

  socket
    .to(roomId)
    .emit("peer-left");

  await socket.leave(roomId);

  socket.data.roomId = null;

  console.log(
    `Socket ${socket.id} left ${roomId}`,
  );
}

// ============================================================
// START SERVER
// ============================================================

httpServer.listen(
  PORT,
  "0.0.0.0",
  () => {
    console.log(
      `Signaling server running on port ${PORT}`,
    );
  },
);