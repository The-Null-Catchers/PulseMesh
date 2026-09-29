"use client";

import { BrowserMeshMediaSession } from "@pulsemesh/sdk";
import { useQueryClient } from "@tanstack/react-query";
import {
  Dispatch,
  MutableRefObject,
  SetStateAction,
  useEffect,
  useRef,
  useState,
} from "react";
import { request, WS_URL } from "../lib/api";
import type { ActiveCall, CallParticipant, PresenceMember } from "../lib/types";

type SocketState = "connecting" | "ready" | "reconnecting";

type UsePulseMeshRealtimeInput = {
  token: string;
  activeRoom: string | null;
  activeMessageKey: string | null;
  workspaceId: string | null;
  currentUserId: string | null;
  socketRef: MutableRefObject<WebSocket | null>;
  activeCallRef: MutableRefObject<ActiveCall | null>;
  activeCallRoomRef: MutableRefObject<string | null>;
  mediaSessionRef: MutableRefObject<BrowserMeshMediaSession | null>;
  selfParticipantIdRef: MutableRefObject<string | null>;
  setActiveCall: Dispatch<SetStateAction<ActiveCall | null>>;
  setActiveCallRoom: Dispatch<SetStateAction<string | null>>;
  setLocalVideoStream: Dispatch<SetStateAction<MediaStream | null>>;
  setRemoteStreams: Dispatch<SetStateAction<Record<string, MediaStream>>>;
  setCameraEnabled: Dispatch<SetStateAction<boolean>>;
  setScreenSharing: Dispatch<SetStateAction<boolean>>;
  setMuted: Dispatch<SetStateAction<boolean>>;
  setDeafened: Dispatch<SetStateAction<boolean>>;
  setCallError: Dispatch<SetStateAction<string | null>>;
};

export function usePulseMeshRealtime({
  token,
  activeRoom,
  activeMessageKey,
  workspaceId,
  currentUserId,
  socketRef,
  activeCallRef,
  activeCallRoomRef,
  mediaSessionRef,
  selfParticipantIdRef,
  setActiveCall,
  setActiveCallRoom,
  setLocalVideoStream,
  setRemoteStreams,
  setCameraEnabled,
  setScreenSharing,
  setMuted,
  setDeafened,
  setCallError,
}: UsePulseMeshRealtimeInput) {
  const queryClient = useQueryClient();
  const [socketState, setSocketState] = useState<SocketState>("connecting");
  const [typingUserIds, setTypingUserIds] = useState<string[]>([]);
  const typingTimersRef = useRef<
    Map<string, ReturnType<typeof setTimeout>>
  >(new Map());
  const retryRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const reconnectAttempt = useRef(0);

  useEffect(() => {
    if (!activeRoom || !activeMessageKey) return;

    let cancelled = false;

    const connect = async () => {
      setSocketState(
        reconnectAttempt.current > 0 ? "reconnecting" : "connecting",
      );

      try {
        const { ticket } = await request<{ ticket: string }>(
          "/realtime/ticket",
          token,
          { method: "POST", body: "{}" },
        );
        if (cancelled) return;

        const url = new URL(WS_URL);
        url.searchParams.set("ticket", ticket);

        const socket = new WebSocket(url);
        socketRef.current = socket;

        socket.onopen = () => {
          reconnectAttempt.current = 0;
        };

        socket.onmessage = (message) => {
          let event: any;

          try {
            event = JSON.parse(String(message.data));
          } catch {
            return;
          }

          if (event.type === "session.ready") {
            const sequence = Number(
              sessionStorage.getItem("pulsemesh:last-sequence") ?? "0",
            );

            socket.send(
              JSON.stringify({
                type: "session.resume",
                lastSequence: Number.isFinite(sequence) ? sequence : 0,
                rooms: [
                  activeRoom,
                  workspaceId ? `workspace:${workspaceId}` : null,
                  activeCallRoomRef.current,
                ].filter((room): room is string => Boolean(room)),
              }),
            );
            return;
          }

          if (event.type === "session.resumed") {
            socket.send(
              JSON.stringify({
                type: "room.subscribe",
                room: activeRoom,
              }),
            );
            socket.send(
              JSON.stringify({
                type: "view.active",
                room: activeRoom,
              }),
            );
            setSocketState("ready");

            if (event.truncated) {
              void queryClient.invalidateQueries({
                queryKey: ["messages", activeMessageKey],
              });
            }
            return;
          }

          if (typeof event.sequence === "number") {
            sessionStorage.setItem(
              "pulsemesh:last-sequence",
              String(event.sequence),
            );
          }

          if (
            event.type === "presence.updated" &&
            event.room === `workspace:${workspaceId}`
          ) {
            queryClient.setQueryData<{ items: PresenceMember[] }>(
              ["presence", workspaceId],
              (current) => ({
                items: (current?.items ?? []).map((member) =>
                  member.userId === event.payload.userId
                    ? {
                        ...member,
                        status: event.payload.status,
                        customText: event.payload.customText,
                        lastSeenAt: event.payload.lastSeenAt,
                        connectedDevices: event.payload.connectedDevices,
                        activeWorkspaceId: event.payload.activeWorkspaceId,
                      }
                    : member,
                ),
              }),
            );
            return;
          }

          if (
            event.type === "call.signal" &&
            activeCallRef.current &&
            event.payload.callId === activeCallRef.current.id
          ) {
            void mediaSessionRef.current
              ?.handleSignal(
                event.payload.fromParticipantId,
                event.payload.signal,
              )
              .catch((error) =>
                setCallError(
                  error instanceof Error
                    ? error.message
                    : "WebRTC signaling failed",
                ),
              );
            return;
          }

          if (
            activeCallRef.current &&
            event.payload?.callId === activeCallRef.current.id &&
            event.type === "call.participant.joined"
          ) {
            const participant = event.payload.participant as CallParticipant;

            setActiveCall((current) =>
              current
                ? {
                    ...current,
                    participants: [
                      ...current.participants.filter(
                        (item) => item.id !== participant.id,
                      ),
                      participant,
                    ],
                  }
                : current,
            );

            const selfId = selfParticipantIdRef.current;
            if (selfId && participant.id !== selfId) {
              void mediaSessionRef.current
                ?.connectPeer(participant.id, selfId < participant.id)
                .catch(() => undefined);
            }
            return;
          }

          if (
            activeCallRef.current &&
            event.payload?.callId === activeCallRef.current.id &&
            event.type === "call.participant.updated"
          ) {
            const participant = event.payload.participant as CallParticipant;

            setActiveCall((current) =>
              current
                ? {
                    ...current,
                    participants: current.participants.map((item) =>
                      item.id === participant.id ? participant : item,
                    ),
                  }
                : current,
            );
            return;
          }

          if (
            activeCallRef.current &&
            event.payload?.callId === activeCallRef.current.id &&
            event.type === "call.participant.left"
          ) {
            const participant = event.payload.participant as CallParticipant;

            setActiveCall((current) =>
              current
                ? {
                    ...current,
                    participants: current.participants.filter(
                      (item) => item.id !== participant.id,
                    ),
                  }
                : current,
            );

            setRemoteStreams((current) => {
              const next = { ...current };
              delete next[participant.id];
              return next;
            });
            return;
          }

          if (
            activeCallRef.current &&
            event.type === "call.ended" &&
            event.payload.callId === activeCallRef.current.id
          ) {
            mediaSessionRef.current?.leave();
            mediaSessionRef.current = null;
            selfParticipantIdRef.current = null;
            activeCallRef.current = null;
            activeCallRoomRef.current = null;
            setActiveCall(null);
            setActiveCallRoom(null);
            setLocalVideoStream(null);
            setRemoteStreams({});
            setCameraEnabled(false);
            setScreenSharing(false);
            setMuted(false);
            setDeafened(false);
            return;
          }

          if (
            event.room === activeRoom &&
            (event.type.startsWith("message.") ||
              event.type.startsWith("reaction."))
          ) {
            void queryClient.invalidateQueries({
              queryKey: ["messages", activeMessageKey],
            });
          }

          if (
            event.room === activeRoom &&
            (event.type === "typing.started" ||
              event.type === "typing.stopped")
          ) {
            const typingUserId = String(event.payload?.userId ?? "");
            if (!typingUserId || typingUserId === currentUserId) return;

            const existingTimer = typingTimersRef.current.get(typingUserId);
            if (existingTimer) {
              clearTimeout(existingTimer);
              typingTimersRef.current.delete(typingUserId);
            }

            if (event.type === "typing.stopped") {
              setTypingUserIds((current) =>
                current.filter((userId) => userId !== typingUserId),
              );
              return;
            }

            const expiresAt = Date.parse(
              String(event.payload?.expiresAt ?? ""),
            );
            const remainingMs = Number.isFinite(expiresAt)
              ? expiresAt - Date.now()
              : 8_000;

            if (remainingMs <= 0) {
              setTypingUserIds((current) =>
                current.filter((userId) => userId !== typingUserId),
              );
              return;
            }

            setTypingUserIds((current) =>
              current.includes(typingUserId)
                ? current
                : [...current, typingUserId],
            );

            const timer = setTimeout(() => {
              typingTimersRef.current.delete(typingUserId);
              setTypingUserIds((current) =>
                current.filter((userId) => userId !== typingUserId),
              );
            }, remainingMs);
            typingTimersRef.current.set(typingUserId, timer);
          }
        };

        socket.onclose = () => {
          if (cancelled) return;

          setSocketState("reconnecting");
          reconnectAttempt.current += 1;
          const delay = Math.min(
            1000 * 2 ** Math.min(reconnectAttempt.current, 5),
            30000,
          );
          retryRef.current = setTimeout(connect, delay);
        };

        socket.onerror = () => socket.close();
      } catch {
        if (cancelled) return;

        setSocketState("reconnecting");
        reconnectAttempt.current += 1;
        retryRef.current = setTimeout(
          connect,
          Math.min(1000 * 2 ** reconnectAttempt.current, 30000),
        );
      }
    };

    void connect();

    return () => {
      cancelled = true;
      if (retryRef.current) clearTimeout(retryRef.current);
      socketRef.current?.close(1000, "Conversation changed");
      socketRef.current = null;
      for (const timer of typingTimersRef.current.values()) {
        clearTimeout(timer);
      }
      typingTimersRef.current.clear();
      setTypingUserIds([]);
    };
  }, [
    activeCallRef,
    activeCallRoomRef,
    activeMessageKey,
    activeRoom,
    currentUserId,
    mediaSessionRef,
    queryClient,
    selfParticipantIdRef,
    setActiveCall,
    setActiveCallRoom,
    setCallError,
    setCameraEnabled,
    setDeafened,
    setLocalVideoStream,
    setMuted,
    setRemoteStreams,
    setScreenSharing,
    socketRef,
    token,
    workspaceId,
  ]);

  useEffect(() => {
    if (socketState !== "ready") return;

    const heartbeat = () => {
      if (socketRef.current?.readyState === WebSocket.OPEN) {
        socketRef.current.send(
          JSON.stringify({
            type: "presence.heartbeat",
          }),
        );
      }
    };

    heartbeat();
    const timer = window.setInterval(heartbeat, 25_000);
    return () => window.clearInterval(timer);
  }, [socketState]);

  return {
    socketRef,
    socketState,
    typingUserIds,
  };
}
