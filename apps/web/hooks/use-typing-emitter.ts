"use client";

import { RefObject, useCallback, useEffect, useRef } from "react";

const TYPING_REFRESH_MS = 2500;
const TYPING_IDLE_MS = 3500;

type TypingEventType = "typing.started" | "typing.stopped";

function sendTypingEvent(
  socket: WebSocket | null,
  type: TypingEventType,
  room: string,
) {
  if (socket?.readyState !== WebSocket.OPEN) return false;

  socket.send(
    JSON.stringify({
      type,
      room,
    }),
  );
  return true;
}

export function useTypingEmitter({
  room,
  socketRef,
}: {
  room: string | null;
  socketRef: RefObject<WebSocket | null>;
}) {
  const typingRoomRef = useRef<string | null>(null);
  const lastStartedAtRef = useRef(0);
  const idleTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const clearIdleTimer = useCallback(() => {
    if (!idleTimerRef.current) return;
    clearTimeout(idleTimerRef.current);
    idleTimerRef.current = null;
  }, []);

  const stopTyping = useCallback(() => {
    clearIdleTimer();

    const typingRoom = typingRoomRef.current;
    if (!typingRoom) return;

    sendTypingEvent(socketRef.current, "typing.stopped", typingRoom);
    typingRoomRef.current = null;
    lastStartedAtRef.current = 0;
  }, [clearIdleTimer, socketRef]);

  const updateTyping = useCallback(
    (value: string) => {
      if (!room) {
        stopTyping();
        return;
      }

      if (!value.trim()) {
        stopTyping();
        return;
      }

      if (typingRoomRef.current && typingRoomRef.current !== room) {
        sendTypingEvent(
          socketRef.current,
          "typing.stopped",
          typingRoomRef.current,
        );
        typingRoomRef.current = null;
        lastStartedAtRef.current = 0;
      }

      const now = Date.now();
      const shouldStart =
        typingRoomRef.current !== room ||
        now - lastStartedAtRef.current >= TYPING_REFRESH_MS;

      if (shouldStart) {
        const sent = sendTypingEvent(
          socketRef.current,
          "typing.started",
          room,
        );
        if (sent) {
          typingRoomRef.current = room;
          lastStartedAtRef.current = now;
        }
      }

      clearIdleTimer();
      idleTimerRef.current = setTimeout(() => {
        stopTyping();
      }, TYPING_IDLE_MS);
    },
    [clearIdleTimer, room, socketRef, stopTyping],
  );

  useEffect(() => {
    return () => {
      stopTyping();
    };
  }, [room, stopTyping]);

  return {
    updateTyping,
    stopTyping,
  };
}
