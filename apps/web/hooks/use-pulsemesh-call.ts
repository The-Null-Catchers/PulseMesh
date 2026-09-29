"use client";

import { BrowserMeshMediaSession } from "@pulsemesh/sdk";
import { MutableRefObject, useRef, useState } from "react";
import { request } from "../lib/api";
import { tokenSubject } from "../lib/session";
import type { ActiveCall } from "../lib/types";

export function usePulseMeshCall({
  token,
  activeRoom,
  socketRef,
}: {
  token: string;
  activeRoom: string | null;
  socketRef: MutableRefObject<WebSocket | null>;
}) {
  const [activeCall, setActiveCall] = useState<ActiveCall | null>(null);
  const [activeCallRoom, setActiveCallRoom] = useState<string | null>(null);
  const [callError, setCallError] = useState<string | null>(null);
  const [muted, setMuted] = useState(false);
  const [deafened, setDeafened] = useState(false);
  const [cameraEnabled, setCameraEnabled] = useState(false);
  const [screenSharing, setScreenSharing] = useState(false);
  const [localVideoStream, setLocalVideoStream] = useState<MediaStream | null>(
    null,
  );
  const [remoteStreams, setRemoteStreams] = useState<
    Record<string, MediaStream>
  >({});

  const mediaSessionRef = useRef<BrowserMeshMediaSession | null>(null);
  const selfParticipantIdRef = useRef<string | null>(null);
  const activeCallRef = useRef<ActiveCall | null>(null);
  const activeCallRoomRef = useRef<string | null>(null);

  function resetCallState() {
    mediaSessionRef.current?.leave();
    mediaSessionRef.current = null;
    selfParticipantIdRef.current = null;
    activeCallRef.current = null;
    activeCallRoomRef.current = null;
    setActiveCall(null);
    setActiveCallRoom(null);
    setLocalVideoStream(null);
    setRemoteStreams({});
    setMuted(false);
    setDeafened(false);
    setCameraEnabled(false);
    setScreenSharing(false);
  }

  async function startCall(input: {
    channelId?: string;
    conversationId?: string;
    kind: "voice" | "video";
  }) {
    if (activeCall) return;

    setCallError(null);
    let startedCallId: string | null = null;

    try {
      const [{ iceServers }, call] = await Promise.all([
        request<{ iceServers: RTCIceServer[] }>("/calls/ice-config", token),
        request<ActiveCall>("/calls", token, {
          method: "POST",
          body: JSON.stringify(input),
        }),
      ]);

      startedCallId = call.id;
      const userId = tokenSubject(token);
      const selfParticipant = call.participants.find(
        (participant) => participant.userId === userId,
      );

      if (!selfParticipant) {
        throw new Error("Current call participant could not be resolved");
      }

      const room = call.channelId
        ? `channel:${call.channelId}`
        : `conversation:${call.conversationId}`;

      const media = new BrowserMeshMediaSession({
        iceServers,
        sendSignal: (targetParticipantId, signal) => {
          if (socketRef.current?.readyState !== WebSocket.OPEN) return;

          socketRef.current.send(
            JSON.stringify({
              type: "call.signal",
              callId: call.id,
              targetParticipantId,
              signal,
            }),
          );
        },
        onRemoteStream: (participantId, stream) => {
          setRemoteStreams((current) => ({
            ...current,
            [participantId]: stream,
          }));
        },
        onScreenShareEnded: () => {
          setScreenSharing(false);
          void request(`/calls/${call.id}/participant`, token, {
            method: "PATCH",
            body: JSON.stringify({ screenSharing: false }),
          }).catch(() => undefined);
        },
      });

      mediaSessionRef.current = media;
      selfParticipantIdRef.current = selfParticipant.id;
      activeCallRef.current = call;
      activeCallRoomRef.current = room;
      setActiveCall(call);
      setActiveCallRoom(room);

      socketRef.current?.send(
        JSON.stringify({
          type: "room.subscribe",
          room,
        }),
      );

      await media.startAudio();

      if (call.kind === "video") {
        const stream = await media.startCamera();
        setLocalVideoStream(stream);
        setCameraEnabled(true);

        await request(`/calls/${call.id}/participant`, token, {
          method: "PATCH",
          body: JSON.stringify({ cameraEnabled: true }),
        });
      }

      for (const participant of call.participants) {
        if (participant.id === selfParticipant.id) continue;

        await media.connectPeer(
          participant.id,
          selfParticipant.id < participant.id,
        );
      }
    } catch (error) {
      if (startedCallId) {
        void request(`/calls/${startedCallId}/leave`, token, {
          method: "POST",
          body: "{}",
        }).catch(() => undefined);
      }

      resetCallState();
      setCallError(
        error instanceof Error ? error.message : "Could not start call",
      );
    }
  }

  async function updateParticipantState(
    patch: Partial<{
      muted: boolean;
      deafened: boolean;
      cameraEnabled: boolean;
      screenSharing: boolean;
    }>,
  ) {
    if (!activeCall) return;

    await request(`/calls/${activeCall.id}/participant`, token, {
      method: "PATCH",
      body: JSON.stringify(patch),
    });
  }

  async function toggleMuted() {
    if (!activeCall) return;

    const next = !muted;
    mediaSessionRef.current?.setMuted(next);
    setMuted(next);

    try {
      await updateParticipantState({ muted: next });
    } catch (error) {
      mediaSessionRef.current?.setMuted(!next);
      setMuted(!next);
      setCallError(error instanceof Error ? error.message : "Mute failed");
    }
  }

  async function toggleDeafened() {
    if (!activeCall) return;

    const next = !deafened;
    mediaSessionRef.current?.setDeafened(next);
    setDeafened(next);

    try {
      await updateParticipantState({ deafened: next });
    } catch (error) {
      mediaSessionRef.current?.setDeafened(!next);
      setDeafened(!next);
      setCallError(error instanceof Error ? error.message : "Deafen failed");
    }
  }

  async function toggleCamera() {
    if (!activeCall || activeCall.kind !== "video") return;

    const media = mediaSessionRef.current;
    if (!media) return;

    try {
      if (!cameraEnabled) {
        const stream = await media.startCamera();
        setLocalVideoStream(stream);
        media.setCameraEnabled(true);
      } else {
        media.setCameraEnabled(false);
      }

      const next = !cameraEnabled;
      setCameraEnabled(next);
      await updateParticipantState({ cameraEnabled: next });
    } catch (error) {
      setCallError(error instanceof Error ? error.message : "Camera failed");
    }
  }

  async function toggleScreenShare() {
    if (!activeCall?.conversationId) return;

    const media = mediaSessionRef.current;
    if (!media) return;

    try {
      if (screenSharing) {
        await media.stopScreenShare();
        setScreenSharing(false);
        await updateParticipantState({ screenSharing: false });
      } else {
        const stream = await media.startScreenShare();
        setLocalVideoStream(stream);
        setScreenSharing(true);
        await updateParticipantState({ screenSharing: true });
      }
    } catch (error) {
      setCallError(
        error instanceof Error ? error.message : "Screen sharing failed",
      );
    }
  }

  async function leaveCall() {
    if (!activeCall) return;

    const callId = activeCall.id;
    const room = activeCallRoom;

    try {
      await request(`/calls/${callId}/leave`, token, {
        method: "POST",
        body: "{}",
      });
    } finally {
      resetCallState();

      if (room && room !== activeRoom) {
        socketRef.current?.send(
          JSON.stringify({
            type: "room.unsubscribe",
            room,
          }),
        );
      }
    }
  }

  return {
    activeCall,
    activeCallRoom,
    callError,
    muted,
    deafened,
    cameraEnabled,
    screenSharing,
    localVideoStream,
    remoteStreams,
    mediaSessionRef,
    selfParticipantIdRef,
    activeCallRef,
    activeCallRoomRef,
    setActiveCall,
    setActiveCallRoom,
    setCallError,
    setMuted,
    setDeafened,
    setCameraEnabled,
    setScreenSharing,
    setLocalVideoStream,
    setRemoteStreams,
    startCall,
    toggleMuted,
    toggleDeafened,
    toggleCamera,
    toggleScreenShare,
    leaveCall,
  };
}
