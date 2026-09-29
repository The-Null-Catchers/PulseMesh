"use client";

import {
  QueryClient,
  QueryClientProvider,
  useMutation,
  useQuery,
  useQueryClient,
} from "@tanstack/react-query";
import {
  Bell,
  Bookmark,
  ChevronDown,
  Hash,
  Headphones,
  Loader2,
  LockKeyhole,
  LogOut,
  MessageCircle,
  Mic,
  MicOff,
  MonitorUp,
  FileText,
  MessageSquareReply,
  Paperclip,
  Pencil,
  Phone,
  PhoneOff,
  Pin,
  Plus,
  RotateCcw,
  Search,
  Send,
  Smile,
  Sparkles,
  Trash2,
  Users,
  Video,
  VideoOff,
  X,
  Volume2,
  Wifi,
  WifiOff,
} from "lucide-react";
import {
  FormEvent,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import { AuthScreen } from "../components/auth-screen";
import { RemoteMedia } from "../components/remote-media";
import { useFileUploads } from "../hooks/use-file-uploads";
import { useGlobalSearch } from "../hooks/use-global-search";
import { useMessageActions } from "../hooks/use-message-actions";
import { useNotifications } from "../hooks/use-notifications";
import { usePulseMeshCall } from "../hooks/use-pulsemesh-call";
import { usePulseMeshRealtime } from "../hooks/use-pulsemesh-realtime";
import { request, setAccessTokenRefresher } from "../lib/api";
import { conversationLabel, initials } from "../lib/display";
import { tokenExpiresAt, tokenSubject } from "../lib/session";
import type {
  Channel,
  Conversation,
  Message,
  Page,
  PresenceMember,
  SearchUser,
  ThreadReply,
  Workspace,
} from "../lib/types";

function WorkspaceApp({
  token,
  onLoggedOut,
}: {
  token: string;
  onLoggedOut: () => void;
}) {
  const queryClient = useQueryClient();
  const currentUserId = tokenSubject(token);
  const [workspaceId, setWorkspaceId] = useState<string | null>(null);
  const [channelId, setChannelId] = useState<string | null>(null);
  const [conversationId, setConversationId] = useState<string | null>(null);
  const [composer, setComposer] = useState("");
  const [newConversationOpen, setNewConversationOpen] = useState(false);
  const [userSearch, setUserSearch] = useState("");
  const [selectedMemberIds, setSelectedMemberIds] = useState<string[]>([]);
  const [groupName, setGroupName] = useState("");
  const [activeThread, setActiveThread] = useState<Message | null>(null);
  const [threadComposer, setThreadComposer] = useState("");
  const socketRef = useRef<WebSocket | null>(null);
  const fileInputRef = useRef<HTMLInputElement | null>(null);
  const lastReadRef = useRef<Record<string, string>>({});

  const {
    searchOpen,
    setSearchOpen,
    searchQuery,
    setSearchQuery,
    searchResults,
  } = useGlobalSearch(token);

  const {
    notificationsOpen,
    setNotificationsOpen,
    notifications,
    markNotificationRead,
    markAllNotificationsRead,
    unreadNotificationCount,
  } = useNotifications(token);

  const workspaces = useQuery({
    queryKey: ["workspaces"],
    queryFn: () => request<{ items: Workspace[] }>("/workspaces", token),
  });

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
        event.preventDefault();
        setSearchOpen(true);
      }
      if (event.key === "Escape") {
        setSearchOpen(false);
        setNotificationsOpen(false);
      }
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, []);

  useEffect(() => {
    const first = workspaces.data?.items[0];
    if (!workspaceId && first) setWorkspaceId(first.id);
  }, [workspaceId, workspaces.data]);

  const channels = useQuery({
    queryKey: ["channels", workspaceId],
    enabled: Boolean(workspaceId),
    queryFn: () =>
      request<{ items: Channel[] }>(
        `/workspaces/${workspaceId}/channels`,
        token,
      ),
  });

  const conversations = useQuery({
    queryKey: ["conversations"],
    queryFn: () => request<{ items: Conversation[] }>("/conversations", token),
  });

  const currentConversation = conversations.data?.items.find(
    (item) => item.id === conversationId,
  );
  const isEncryptedConversation =
    currentConversation?.encryption_mode === "e2ee_v1";

  const {
    uploads,
    setUploads,
    uploadError,
    uploadFile,
    cancelUpload,
    downloadAttachment,
  } = useFileUploads({
    token,
    isEncryptedConversation,
  });

  const userSearchResults = useQuery({
    queryKey: ["user-search", userSearch],
    enabled: newConversationOpen && userSearch.trim().length >= 2,
    queryFn: () =>
      request<{ users: SearchUser[] }>(
        `/search?q=${encodeURIComponent(userSearch.trim())}&limit=10`,
        token,
      ),
  });

  const createConversation = useMutation({
    mutationFn: async () => {
      if (!selectedMemberIds.length) {
        throw new Error("Choose at least one person");
      }
      const kind = selectedMemberIds.length === 1 ? "direct" : "group";
      return request<{ id: string }>("/conversations", token, {
        method: "POST",
        body: JSON.stringify({
          kind,
          memberIds: selectedMemberIds,
          ...(kind === "group" && groupName.trim()
            ? { name: groupName.trim() }
            : {}),
        }),
      });
    },
    onSuccess: async ({ id }) => {
      await queryClient.invalidateQueries({ queryKey: ["conversations"] });
      setChannelId(null);
      setConversationId(id);
      setNewConversationOpen(false);
      setUserSearch("");
      setSelectedMemberIds([]);
      setGroupName("");
    },
  });

  useEffect(() => {
    const textChannels =
      channels.data?.items.filter((item) => item.kind === "text") ?? [];
    if (!channelId && !conversationId && textChannels.length > 0) {
      setChannelId(textChannels[0]!.id);
    }
  }, [channelId, conversationId, channels.data]);

  const activeRoom = channelId
    ? `channel:${channelId}`
    : conversationId
      ? `conversation:${conversationId}`
      : null;
  const activeMessageKey = channelId ?? conversationId;

  const {
    activeCall,
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
  } = usePulseMeshCall({
    token,
    activeRoom,
    socketRef,
  });

  const activeMessagesPath = channelId
    ? `/channels/${channelId}/messages?limit=50`
    : conversationId
      ? `/conversations/${conversationId}/messages?limit=50`
      : null;

  const messages = useQuery({
    queryKey: ["messages", activeMessageKey],
    enabled: Boolean(activeMessagesPath),
    queryFn: () => request<Page<Message>>(activeMessagesPath!, token),
  });

  const presence = useQuery({
    queryKey: ["presence", workspaceId],
    enabled: Boolean(workspaceId),
    queryFn: () =>
      request<{ items: PresenceMember[] }>(
        `/workspaces/${workspaceId}/presence`,
        token,
      ),
  });

  const thread = useQuery({
    queryKey: ["thread", activeThread?.id],
    enabled: Boolean(activeThread?.id),
    queryFn: () =>
      request<{ items: ThreadReply[] }>(
        `/messages/${activeThread!.id}/thread`,
        token,
      ),
  });

  const { socketState, typing } = usePulseMeshRealtime({
    token,
    activeRoom,
    activeMessageKey,
    workspaceId,
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
  });

  const {
    sendMessage,
    retryFailedMessage,
    reactionMutation,
    editMessage,
    deleteMessage,
    bookmarkMessage,
    pinMessage,
    sendThreadReply,
    editingMessageId,
    setEditingMessageId,
    editBody,
    setEditBody,
    messageActionError,
    setMessageActionError,
  } = useMessageActions({
    token,
    activeMessageKey,
    channelId,
    conversationId,
    uploads,
    setUploads,
    activeThread,
    threadComposer,
    setThreadComposer,
  });

  const logout = useMutation({
    mutationFn: () =>
      request("/auth/logout", token, {
        method: "POST",
        body: "{}",
      }),
    onSettled: onLoggedOut,
  });

  useEffect(() => {
    const latestMessage = messages.data?.items[0];
    if (!latestMessage || !activeMessageKey || socketState !== "ready") return;

    if (lastReadRef.current[activeMessageKey] === latestMessage.id) return;
    lastReadRef.current[activeMessageKey] = latestMessage.id;

    void request("/read-state", token, {
      method: "PUT",
      body: JSON.stringify(
        channelId
          ? {
              channelId,
              lastReadMessageId: latestMessage.id,
            }
          : {
              conversationId,
              lastReadMessageId: latestMessage.id,
            },
      ),
    }).catch(() => {
      delete lastReadRef.current[activeMessageKey];
    });
  }, [
    activeMessageKey,
    channelId,
    conversationId,
    messages.data,
    socketState,
    token,
  ]);

  const currentWorkspace = workspaces.data?.items.find(
    (item) => item.id === workspaceId,
  );
  const currentChannel = channels.data?.items.find(
    (item) => item.id === channelId,
  );
  const currentTitle =
    currentChannel?.name ??
    (currentConversation
      ? conversationLabel(currentConversation, currentUserId)
      : "Select a conversation");
  const textChannels =
    channels.data?.items.filter((item) => item.kind === "text") ?? [];
  const voiceChannels =
    channels.data?.items.filter((item) => item.kind === "voice") ?? [];
  const orderedMessages = useMemo(
    () => [...(messages.data?.items ?? [])].reverse(),
    [messages.data],
  );
  function submitMessage(event: FormEvent) {
    event.preventDefault();
    const body = composer.trim();
    if (isEncryptedConversation) {
      setMessageActionError(
        "This conversation is end-to-end encrypted. Sending from the web client is disabled until libsignal support is available.",
      );
      return;
    }
    const readyUploads = uploads.filter(
      (item) => item.status === "ready" && item.fileId,
    );
    const hasPendingUploads = uploads.some(
      (item) => item.status === "uploading" || item.status === "processing",
    );
    if (
      (!body && readyUploads.length === 0) ||
      hasPendingUploads ||
      !activeRoom ||
      sendMessage.isPending
    ) {
      return;
    }
    setComposer("");
    sendMessage.mutate({
      body,
      clientMessageId: crypto.randomUUID(),
      attachmentIds: readyUploads.map((item) => item.fileId!),
    });
    socketRef.current?.send(
      JSON.stringify({
        type: "typing.stopped",
        room: activeRoom,
      }),
    );
  }

  function onComposerChange(value: string) {
    setComposer(value);
    if (activeRoom && socketRef.current?.readyState === WebSocket.OPEN) {
      socketRef.current.send(
        JSON.stringify({
          type: value ? "typing.started" : "typing.stopped",
          room: activeRoom,
        }),
      );
    }
  }

  if (workspaces.isLoading) {
    return (
      <main className="grid min-h-screen place-items-center">
        <Loader2 className="size-7 animate-spin text-[#68e0cf]" />
      </main>
    );
  }

  if (
    !workspaces.data?.items.length &&
    !conversations.isLoading &&
    !conversations.data?.items.length
  ) {
    return (
      <main className="grid min-h-screen place-items-center p-6">
        <div className="max-w-lg rounded-[28px] border border-white/10 bg-[#09151a]/90 p-8 text-center">
          <Sparkles className="mx-auto size-7 text-[#68e0cf]" />
          <h1 className="mt-4 text-2xl font-semibold">
            Your PulseMesh account is ready
          </h1>
          <p className="mt-3 text-sm leading-6 text-slate-400">
            Create a workspace or start a direct conversation, then this client
            will load it immediately.
          </p>
          <button
            onClick={() => logout.mutate()}
            className="mt-6 rounded-2xl border border-white/10 px-4 py-2 text-sm"
          >
            Sign out
          </button>
        </div>
      </main>
    );
  }

  return (
    <main className="min-h-screen p-3 md:p-4">
      <div className="mx-auto grid h-[calc(100vh-24px)] max-w-[1700px] grid-cols-[72px_minmax(0,1fr)] overflow-hidden rounded-[28px] border border-white/10 bg-[#09151a]/80 shadow-2xl shadow-black/30 sm:grid-cols-[72px_260px_minmax(0,1fr)] md:h-[calc(100vh-32px)] xl:grid-cols-[72px_270px_minmax(0,1fr)_280px]">
        <aside className="flex flex-col items-center gap-3 border-r border-white/8 bg-[#071116]/80 py-4">
          <div className="mb-2 grid size-11 place-items-center rounded-2xl bg-[linear-gradient(135deg,#68e0cf,#73a7ff)] font-black text-[#061013]">
            P
          </div>
          {(workspaces.data?.items ?? []).map((workspace) => (
            <button
              key={workspace.id}
              onClick={() => {
                setWorkspaceId(workspace.id);
                setConversationId(null);
                setChannelId(null);
              }}
              className={
                "grid size-11 place-items-center rounded-2xl border text-sm font-semibold transition " +
                (workspace.id === workspaceId
                  ? "border-[#68e0cf]/35 bg-[#68e0cf]/12 text-[#9af5e8]"
                  : "border-white/8 bg-white/[0.035] text-slate-400 hover:bg-white/[0.07]")
              }
              aria-label={workspace.name}
            >
              {initials(workspace.name) || "W"}
            </button>
          ))}
          <button className="grid size-11 place-items-center rounded-2xl border border-dashed border-white/15 text-slate-500">
            <Plus className="size-4" />
          </button>
          <button
            onClick={() => logout.mutate()}
            className="mt-auto grid size-11 place-items-center rounded-2xl border border-white/8 text-slate-500 hover:text-white"
            aria-label="Sign out"
          >
            <LogOut className="size-4" />
          </button>
        </aside>

        <aside className="hidden border-r border-white/8 bg-[#0a151a]/85 sm:flex sm:flex-col">
          <div className="flex h-16 items-center justify-between border-b border-white/8 px-4">
            <div className="min-w-0">
              <p className="text-xs uppercase tracking-[0.18em] text-[#68e0cf]/70">
                Workspace
              </p>
              <button className="mt-0.5 flex max-w-full items-center gap-1 font-semibold">
                <span className="truncate">
                  {currentWorkspace?.name ?? "PulseMesh"}
                </span>
                <ChevronDown className="size-4 shrink-0 text-slate-500" />
              </button>
            </div>
          </div>
          <div className="p-3">
            <button
              type="button"
              onClick={() => setSearchOpen(true)}
              className="flex w-full items-center gap-2 rounded-xl border border-white/8 bg-white/[0.035] px-3 py-2 text-left text-sm text-slate-400"
            >
              <Search className="size-4" />
              Search workspace
              <span className="ml-auto rounded-md border border-white/8 px-1.5 py-0.5 text-[10px]">
                ⌘K
              </span>
            </button>
          </div>
          <nav className="flex-1 overflow-y-auto px-3 pb-3">
            <div className="mb-2 flex items-center justify-between px-2 pt-2 text-[11px] font-semibold uppercase tracking-[0.16em] text-slate-500">
              Channels
              <Plus className="size-3.5" />
            </div>
            <div className="space-y-1">
              {textChannels.map((channel) => (
                <button
                  key={channel.id}
                  onClick={() => {
                    setConversationId(null);
                    setChannelId(channel.id);
                  }}
                  className={
                    "flex w-full items-center gap-2 rounded-xl px-2.5 py-2 text-sm " +
                    (channel.id === channelId
                      ? "bg-[linear-gradient(90deg,rgba(104,224,207,.11),rgba(115,167,255,.05))] text-white"
                      : "text-slate-400 hover:bg-white/[0.04] hover:text-slate-200")
                  }
                >
                  <Hash className="size-4 opacity-60" />
                  <span className="truncate">{channel.name}</span>
                </button>
              ))}
            </div>
            <div className="mb-2 mt-6 flex items-center justify-between px-2 text-[11px] font-semibold uppercase tracking-[0.16em] text-slate-500">
              Messages
              <button
                type="button"
                onClick={() => setNewConversationOpen(true)}
                className="rounded-md p-1 hover:bg-white/[0.05] hover:text-slate-300"
                aria-label="Start conversation"
              >
                <Plus className="size-3.5" />
              </button>
            </div>
            <div className="space-y-1">
              {(conversations.data?.items ?? [])
                .slice(0, 12)
                .map((conversation) => {
                  const label = conversationLabel(
                    conversation,
                    currentUserId,
                  );
                  return (
                    <button
                      key={conversation.id}
                      onClick={() => {
                        setChannelId(null);
                        setConversationId(conversation.id);
                      }}
                      className={
                        "flex w-full items-center gap-2 rounded-xl px-2.5 py-2 text-sm " +
                        (conversation.id === conversationId
                          ? "bg-[linear-gradient(90deg,rgba(115,167,255,.11),rgba(104,224,207,.05))] text-white"
                          : "text-slate-400 hover:bg-white/[0.04] hover:text-slate-200")
                      }
                    >
                      <MessageCircle className="size-4 opacity-60" />
                      <span className="truncate">
                        {label || "Conversation"}
                      </span>
                    </button>
                  );
                })}
            </div>

            <div className="mb-2 mt-6 flex items-center justify-between px-2 text-[11px] font-semibold uppercase tracking-[0.16em] text-slate-500">
              Voice
              <Plus className="size-3.5" />
            </div>
            {voiceChannels.length ? (
              voiceChannels.map((channel) => (
                <button
                  key={channel.id}
                  type="button"
                  onClick={() =>
                    void startCall({ channelId: channel.id, kind: "voice" })
                  }
                  className={
                    "flex w-full items-center gap-2 rounded-xl px-2.5 py-2 text-sm " +
                    (activeCall?.channelId === channel.id
                      ? "bg-emerald-400/10 text-emerald-300"
                      : "text-slate-400 hover:bg-white/[0.04]")
                  }
                >
                  <Volume2 className="size-4" />
                  <span className="truncate">{channel.name}</span>
                  {activeCall?.channelId === channel.id && (
                    <span className="ml-auto text-[10px]">Connected</span>
                  )}
                </button>
              ))
            ) : (
              <p className="px-2 text-xs text-slate-600">No voice rooms yet</p>
            )}
          </nav>
        </aside>

        <section className="flex min-w-0 flex-col bg-[#0b171c]/70">
          <header className="flex h-16 items-center gap-3 border-b border-white/8 px-4 md:px-5">
            <div className="grid size-9 place-items-center rounded-xl bg-white/[0.04]">
              {currentConversation ? (
                <MessageCircle className="size-4 text-[#82e9dc]" />
              ) : (
                <Hash className="size-4 text-[#82e9dc]" />
              )}
            </div>
            <div className="min-w-0">
              <div className="flex items-center gap-2">
                <h1 className="font-semibold">{currentTitle}</h1>
                {isEncryptedConversation && (
                  <span
                    className="inline-flex items-center gap-1 rounded-lg border border-[#68e0cf]/15 bg-[#68e0cf]/[0.06] px-2 py-0.5 text-[10px] font-medium text-[#9af5e8]"
                    title="End-to-end encrypted conversation"
                  >
                    <LockKeyhole className="size-3" />
                    E2EE
                  </span>
                )}
              </div>
              <p className="truncate text-xs text-slate-500">
                {currentConversation
                  ? currentConversation.kind === "direct"
                    ? "Direct message"
                    : `${currentConversation.members.length} participants`
                  : (currentChannel?.topic ?? "Realtime team conversation")}
              </p>
            </div>
            <div className="ml-auto flex items-center gap-1">
              <div
                className="mr-2 flex items-center gap-1.5 text-[11px] text-slate-500"
                title={socketState}
              >
                {socketState === "ready" ? (
                  <Wifi className="size-3.5 text-emerald-400" />
                ) : (
                  <WifiOff className="size-3.5 text-amber-400" />
                )}
                {socketState}
              </div>
              {currentConversation && !activeCall && (
                <>
                  <button
                    type="button"
                    onClick={() =>
                      void startCall({
                        conversationId: currentConversation.id,
                        kind: "voice",
                      })
                    }
                    className="rounded-xl p-2 text-slate-500 hover:bg-white/5 hover:text-white"
                    aria-label="Start voice call"
                  >
                    <Phone className="size-4" />
                  </button>
                  <button
                    type="button"
                    onClick={() =>
                      void startCall({
                        conversationId: currentConversation.id,
                        kind: "video",
                      })
                    }
                    className="rounded-xl p-2 text-slate-500 hover:bg-white/5 hover:text-white"
                    aria-label="Start video call"
                  >
                    <Video className="size-4" />
                  </button>
                </>
              )}
              <button
                type="button"
                onClick={() => setSearchOpen(true)}
                className="rounded-xl p-2 text-slate-500 hover:bg-white/5 hover:text-white"
                aria-label="Search"
              >
                <Search className="size-4" />
              </button>
              <button
                type="button"
                onClick={() => setNotificationsOpen(true)}
                className="relative rounded-xl p-2 text-slate-500 hover:bg-white/5 hover:text-white"
                aria-label="Notifications"
              >
                <Bell className="size-4" />
                {unreadNotificationCount > 0 && (
                  <span className="absolute right-0.5 top-0.5 grid min-w-4 place-items-center rounded-full bg-[#68e0cf] px-1 text-[9px] font-bold leading-4 text-[#061013]">
                    {unreadNotificationCount > 99
                      ? "99+"
                      : unreadNotificationCount}
                  </span>
                )}
              </button>
            </div>
          </header>

          {activeCall && (
            <div className="border-b border-white/8 bg-[#081319]/95 px-4 py-3 md:px-6">
              <div className="mx-auto flex max-w-4xl flex-col gap-3">
                <div className="flex flex-wrap items-center gap-3">
                  <div className="flex min-w-0 items-center gap-3">
                    <div className="grid size-10 place-items-center rounded-2xl bg-emerald-400/10 text-emerald-300">
                      {activeCall.kind === "video" ? (
                        <Video className="size-4" />
                      ) : (
                        <Phone className="size-4" />
                      )}
                    </div>
                    <div className="min-w-0">
                      <p className="text-sm font-semibold">
                        {activeCall.kind === "video"
                          ? "Video call"
                          : "Voice call"}
                      </p>
                      <p className="text-xs text-slate-500">
                        {activeCall.participants.length} participant
                        {activeCall.participants.length === 1 ? "" : "s"} · mesh
                        WebRTC
                      </p>
                    </div>
                  </div>

                  <div className="ml-auto flex items-center gap-1.5">
                    <button
                      type="button"
                      onClick={() => void toggleMuted()}
                      className={
                        "rounded-xl p-2 " +
                        (muted
                          ? "bg-rose-400/10 text-rose-300"
                          : "bg-white/[0.04] text-slate-400")
                      }
                      aria-label={muted ? "Unmute" : "Mute"}
                    >
                      {muted ? (
                        <MicOff className="size-4" />
                      ) : (
                        <Mic className="size-4" />
                      )}
                    </button>
                    <button
                      type="button"
                      onClick={() => void toggleDeafened()}
                      className={
                        "rounded-xl p-2 " +
                        (deafened
                          ? "bg-amber-400/10 text-amber-300"
                          : "bg-white/[0.04] text-slate-400")
                      }
                      aria-label={deafened ? "Undeafen" : "Deafen"}
                    >
                      <Headphones className="size-4" />
                    </button>
                    {activeCall.kind === "video" && (
                      <button
                        type="button"
                        onClick={() => void toggleCamera()}
                        className={
                          "rounded-xl p-2 " +
                          (cameraEnabled
                            ? "bg-[#68e0cf]/10 text-[#9af5e8]"
                            : "bg-white/[0.04] text-slate-400")
                        }
                        aria-label={
                          cameraEnabled ? "Turn camera off" : "Turn camera on"
                        }
                      >
                        {cameraEnabled ? (
                          <Video className="size-4" />
                        ) : (
                          <VideoOff className="size-4" />
                        )}
                      </button>
                    )}
                    {activeCall.conversationId && (
                      <button
                        type="button"
                        onClick={() => void toggleScreenShare()}
                        className={
                          "rounded-xl p-2 " +
                          (screenSharing
                            ? "bg-[#68e0cf]/10 text-[#9af5e8]"
                            : "bg-white/[0.04] text-slate-400")
                        }
                        aria-label="Share screen"
                      >
                        <MonitorUp className="size-4" />
                      </button>
                    )}
                    <button
                      type="button"
                      onClick={() => void leaveCall()}
                      className="rounded-xl bg-rose-500/15 p-2 text-rose-300 hover:bg-rose-500/20"
                      aria-label="Leave call"
                    >
                      <PhoneOff className="size-4" />
                    </button>
                  </div>
                </div>

                {callError && (
                  <div className="rounded-xl border border-rose-400/20 bg-rose-400/10 px-3 py-2 text-xs text-rose-200">
                    {callError}
                  </div>
                )}

                {activeCall.kind === "video" && (
                  <div className="grid grid-cols-2 gap-2 md:grid-cols-3">
                    {localVideoStream && (
                      <div className="relative aspect-video overflow-hidden rounded-2xl border border-white/10 bg-black/30">
                        <RemoteMedia stream={localVideoStream} video />
                        <span className="absolute bottom-2 left-2 rounded-lg bg-black/50 px-2 py-1 text-[10px]">
                          You
                        </span>
                      </div>
                    )}
                    {activeCall.participants
                      .filter(
                        (participant) =>
                          participant.id !== selfParticipantIdRef.current &&
                          remoteStreams[participant.id],
                      )
                      .map((participant) => (
                        <div
                          key={participant.id}
                          className="relative aspect-video overflow-hidden rounded-2xl border border-white/10 bg-black/30"
                        >
                          <RemoteMedia
                            stream={remoteStreams[participant.id]!}
                            video
                          />
                          <span className="absolute bottom-2 left-2 rounded-lg bg-black/50 px-2 py-1 text-[10px]">
                            {participant.displayName}
                          </span>
                        </div>
                      ))}
                  </div>
                )}

                {activeCall.kind === "voice" &&
                  Object.entries(remoteStreams).map(
                    ([participantId, stream]) => (
                      <RemoteMedia
                        key={participantId}
                        stream={stream}
                        video={false}
                      />
                    ),
                  )}
              </div>
            </div>
          )}

          <div className="relative flex-1 overflow-y-auto px-4 py-6 md:px-7">
            <div className="mx-auto max-w-3xl">
              {(messageActionError || uploadError) && (
                <div className="mb-4 rounded-2xl border border-rose-400/20 bg-rose-400/10 px-4 py-3 text-sm text-rose-200">
                  {messageActionError || uploadError}
                </div>
              )}
              {messages.isLoading ? (
                <div className="grid h-48 place-items-center">
                  <Loader2 className="size-6 animate-spin text-[#68e0cf]" />
                </div>
              ) : orderedMessages.length ? (
                <div className="space-y-6">
                  {orderedMessages.map((message) => (
                    <article
                      key={message.id}
                      className={
                        "group flex gap-3 rounded-2xl border px-2 py-1.5 transition hover:bg-white/[0.025] " +
                        (message.failed
                          ? "border-rose-400/20 bg-rose-400/[0.035]"
                          : "border-transparent ") +
                        (message.optimistic ? "opacity-60" : "")
                      }
                    >
                      <div className="grid size-10 shrink-0 place-items-center rounded-2xl border border-white/10 bg-white/[0.05] text-xs font-semibold">
                        {initials(message.sender.displayName) || "?"}
                      </div>
                      <div className="min-w-0 flex-1">
                        <div className="flex items-baseline gap-2">
                          <h3 className="text-sm font-semibold">
                            {message.sender.displayName}
                          </h3>
                          <span className="text-[11px] text-slate-600">
                            {new Date(message.createdAt).toLocaleTimeString(
                              [],
                              { hour: "2-digit", minute: "2-digit" },
                            )}
                          </span>
                          {message.editedAt && (
                            <span className="text-[10px] text-slate-600">
                              edited
                            </span>
                          )}
                          {message.failed && (
                            <span className="text-[10px] font-medium text-rose-300">
                              failed
                            </span>
                          )}
                          {message.failed && (
                            <button
                              type="button"
                              onClick={() => retryFailedMessage(message)}
                              disabled={sendMessage.isPending}
                              className="ml-auto flex items-center gap-1 rounded-lg border border-rose-400/20 bg-rose-400/10 px-2 py-1 text-[10px] font-medium text-rose-200 disabled:opacity-40"
                              aria-label="Retry failed message"
                            >
                              <RotateCcw className="size-3" />
                              Retry
                            </button>
                          )}
                          {!message.optimistic && !message.failed && (
                            <div className="ml-auto hidden items-center gap-1 group-hover:flex">
                              {!message.encryptedPayload && (
                                <button
                                  type="button"
                                  onClick={() => setActiveThread(message)}
                                  className="rounded-lg p-1.5 text-slate-500 hover:bg-white/5 hover:text-white"
                                  aria-label="Open thread"
                                >
                                  <MessageSquareReply className="size-3.5" />
                                </button>
                              )}
                              <button
                                type="button"
                                onClick={() =>
                                  bookmarkMessage.mutate(message.id)
                                }
                                className="rounded-lg p-1.5 text-slate-500 hover:bg-white/5 hover:text-white"
                                aria-label="Bookmark message"
                              >
                                <Bookmark className="size-3.5" />
                              </button>
                              <button
                                type="button"
                                onClick={() => pinMessage.mutate(message.id)}
                                className="rounded-lg p-1.5 text-slate-500 hover:bg-white/5 hover:text-white"
                                aria-label="Pin message"
                              >
                                <Pin className="size-3.5" />
                              </button>
                              {!message.encryptedPayload && (
                                <button
                                  type="button"
                                  onClick={() => {
                                    setEditingMessageId(message.id);
                                    setEditBody(message.body);
                                  }}
                                  className="rounded-lg p-1.5 text-slate-500 hover:bg-white/5 hover:text-white"
                                  aria-label="Edit message"
                                >
                                  <Pencil className="size-3.5" />
                                </button>
                              )}
                              <button
                                type="button"
                                onClick={() => deleteMessage.mutate(message.id)}
                                className="rounded-lg p-1.5 text-slate-500 hover:bg-rose-400/10 hover:text-rose-300"
                                aria-label="Delete message"
                              >
                                <Trash2 className="size-3.5" />
                              </button>
                            </div>
                          )}
                        </div>

                        {editingMessageId === message.id ? (
                          <div className="mt-2">
                            <textarea
                              value={editBody}
                              onChange={(event) =>
                                setEditBody(event.target.value)
                              }
                              rows={2}
                              className="w-full resize-none rounded-xl border border-white/10 bg-white/[0.035] px-3 py-2 text-sm outline-none focus:border-[#68e0cf]/40"
                            />
                            <div className="mt-2 flex gap-2">
                              <button
                                type="button"
                                disabled={
                                  !editBody.trim() || editMessage.isPending
                                }
                                onClick={() =>
                                  editMessage.mutate({
                                    messageId: message.id,
                                    body: editBody.trim(),
                                  })
                                }
                                className="rounded-xl bg-[#68e0cf] px-3 py-1.5 text-xs font-semibold text-[#061013] disabled:opacity-40"
                              >
                                Save
                              </button>
                              <button
                                type="button"
                                onClick={() => {
                                  setEditingMessageId(null);
                                  setEditBody("");
                                }}
                                className="rounded-xl border border-white/10 px-3 py-1.5 text-xs text-slate-400"
                              >
                                Cancel
                              </button>
                            </div>
                          </div>
                        ) : message.encryptedPayload ? (
                          <div className="mt-2 flex items-center gap-2 rounded-xl border border-[#68e0cf]/10 bg-[#68e0cf]/[0.04] px-3 py-2 text-sm text-slate-400">
                            <LockKeyhole className="size-4 shrink-0 text-[#68e0cf]" />
                            <span>
                              Encrypted message · decrypt with an E2EE-capable
                              PulseMesh client
                            </span>
                          </div>
                        ) : (
                          <p className="mt-1 whitespace-pre-wrap break-words text-[15px] leading-6 text-slate-300">
                            {message.body}
                          </p>
                        )}

                        {(message.attachments ?? []).length > 0 && (
                          <div className="mt-3 flex flex-wrap gap-2">
                            {(message.attachments ?? []).map((attachment) => (
                              <button
                                key={attachment.id}
                                type="button"
                                onClick={() =>
                                  void downloadAttachment(attachment)
                                }
                                className="flex max-w-xs items-center gap-2 rounded-2xl border border-white/10 bg-white/[0.035] px-3 py-2 text-left hover:bg-white/[0.06]"
                              >
                                <FileText className="size-4 shrink-0 text-[#68e0cf]" />
                                <span className="min-w-0">
                                  <span className="block truncate text-xs font-medium text-slate-300">
                                    {attachment.name}
                                  </span>
                                  <span className="block text-[10px] text-slate-600">
                                    {(attachment.sizeBytes / 1024).toFixed(1)}{" "}
                                    KB
                                  </span>
                                </span>
                              </button>
                            ))}
                          </div>
                        )}

                        {!message.optimistic && !message.failed && (
                          <div className="mt-2 flex flex-wrap items-center gap-1.5">
                            {(message.reactions ?? []).map((reaction) => (
                              <button
                                key={reaction.emoji}
                                type="button"
                                onClick={() =>
                                  reactionMutation.mutate({
                                    messageId: message.id,
                                    emoji: reaction.emoji,
                                    reacted: reaction.reactedByMe,
                                  })
                                }
                                className={
                                  "rounded-xl border px-2 py-1 text-xs transition " +
                                  (reaction.reactedByMe
                                    ? "border-[#68e0cf]/30 bg-[#68e0cf]/10 text-[#9af5e8]"
                                    : "border-white/8 bg-white/[0.03] text-slate-400")
                                }
                              >
                                {reaction.emoji} {reaction.count}
                              </button>
                            ))}
                            {["👍", "🔥", "😂"].map((emoji) => {
                              const existing = (message.reactions ?? []).find(
                                (reaction) => reaction.emoji === emoji,
                              );
                              if (existing) return null;
                              return (
                                <button
                                  key={emoji}
                                  type="button"
                                  onClick={() =>
                                    reactionMutation.mutate({
                                      messageId: message.id,
                                      emoji,
                                      reacted: false,
                                    })
                                  }
                                  className="rounded-xl border border-dashed border-white/8 px-2 py-1 text-xs text-slate-600 hover:text-slate-300"
                                  aria-label={`React with ${emoji}`}
                                >
                                  {emoji}
                                </button>
                              );
                            })}
                          </div>
                        )}
                      </div>
                    </article>
                  ))}
                </div>
              ) : (
                <div className="mt-16 text-center">
                  <Sparkles className="mx-auto size-6 text-[#68e0cf]" />
                  <h2 className="mt-3 text-lg font-semibold">
                    Start the conversation
                  </h2>
                  <p className="mt-1 text-sm text-slate-500">
                    Messages sent here are persisted in PostgreSQL and delivered
                    over WebSockets.
                  </p>
                </div>
              )}
            </div>
          </div>

          <div className="px-4 pb-4 md:px-6 md:pb-5">
            <div className="mx-auto max-w-3xl">
              <div className="mb-1 min-h-5 px-2 text-xs text-slate-600">
                {typing ? "Someone is typing…" : ""}
              </div>
              {isEncryptedConversation && (
                <div className="mb-2 flex items-start gap-2 rounded-2xl border border-[#68e0cf]/10 bg-[#68e0cf]/[0.04] px-4 py-3 text-xs leading-5 text-slate-400">
                  <LockKeyhole className="mt-0.5 size-4 shrink-0 text-[#68e0cf]" />
                  <span>
                    This conversation uses end-to-end encryption. Reading and
                    sending ciphertext on web will be enabled after the
                    libsignal client is completed. Plaintext and attachments are
                    blocked here.
                  </span>
                </div>
              )}
              {uploads.length > 0 && (
                <div className="mb-2 flex flex-wrap gap-2">
                  {uploads.map((item) => (
                    <div
                      key={item.localId}
                      className="flex min-w-[190px] max-w-xs items-center gap-2 rounded-2xl border border-white/10 bg-white/[0.035] px-3 py-2"
                    >
                      <FileText className="size-4 shrink-0 text-[#68e0cf]" />
                      <div className="min-w-0 flex-1">
                        <p className="truncate text-xs font-medium text-slate-300">
                          {item.name}
                        </p>
                        <p className="text-[10px] text-slate-600">
                          {item.status === "uploading"
                            ? `${item.progress}% uploaded`
                            : item.status === "processing"
                              ? "Processing…"
                              : item.status === "ready"
                                ? "Ready to send"
                                : (item.error ?? item.status)}
                        </p>
                        {item.status === "uploading" && (
                          <div className="mt-1 h-1 overflow-hidden rounded-full bg-white/5">
                            <div
                              className="h-full bg-[#68e0cf]"
                              style={{ width: `${item.progress}%` }}
                            />
                          </div>
                        )}
                      </div>
                      {item.status === "failed" ? (
                        <button
                          type="button"
                          onClick={() =>
                            void uploadFile(item.file, item.localId)
                          }
                          className="rounded-lg p-1.5 text-slate-500 hover:text-white"
                          aria-label="Retry upload"
                        >
                          <RotateCcw className="size-3.5" />
                        </button>
                      ) : null}
                      <button
                        type="button"
                        onClick={() => void cancelUpload(item)}
                        className="rounded-lg p-1.5 text-slate-500 hover:text-rose-300"
                        aria-label="Cancel upload"
                      >
                        <X className="size-3.5" />
                      </button>
                    </div>
                  ))}
                </div>
              )}
              <form
                onSubmit={submitMessage}
                onDragOver={(event) => {
                  if (!isEncryptedConversation) event.preventDefault();
                }}
                onDrop={(event) => {
                  event.preventDefault();
                  if (isEncryptedConversation) return;
                  Array.from(event.dataTransfer.files).forEach(
                    (file) => void uploadFile(file),
                  );
                }}
                className="flex items-end gap-2 rounded-2xl border border-white/10 bg-white/[0.045] p-2 shadow-lg shadow-black/10"
              >
                <input
                  ref={fileInputRef}
                  type="file"
                  multiple
                  disabled={isEncryptedConversation}
                  className="hidden"
                  onChange={(event) => {
                    const files = Array.from(event.target.files ?? []);
                    files.forEach((file) => void uploadFile(file));
                    event.currentTarget.value = "";
                  }}
                />
                <button
                  type="button"
                  onClick={() => fileInputRef.current?.click()}
                  disabled={isEncryptedConversation}
                  className="mb-0.5 rounded-xl p-2 text-slate-500 hover:bg-white/5 hover:text-white disabled:cursor-not-allowed disabled:opacity-30"
                  aria-label={
                    isEncryptedConversation
                      ? "Attachments unavailable in encrypted conversation"
                      : "Attach files"
                  }
                >
                  <Paperclip className="size-4" />
                </button>
                <textarea
                  value={composer}
                  onChange={(event) => onComposerChange(event.target.value)}
                  onPaste={(event) => {
                    const files = Array.from(event.clipboardData.files);
                    if (!isEncryptedConversation && files.length > 0) {
                      files.forEach((file) => void uploadFile(file));
                    }
                  }}
                  rows={1}
                  disabled={!activeRoom || isEncryptedConversation}
                  placeholder={
                    isEncryptedConversation
                      ? "Encrypted messaging is not available on web yet"
                      : currentChannel
                        ? `Message #${currentChannel.name}…`
                        : currentConversation
                          ? `Message ${currentTitle}…`
                          : "Select a conversation"
                  }
                  className="max-h-36 min-h-10 flex-1 resize-none bg-transparent px-1 py-2 text-sm outline-none placeholder:text-slate-600"
                  onKeyDown={(event) => {
                    if (
                      event.key === "Enter" &&
                      !event.shiftKey &&
                      !event.nativeEvent.isComposing
                    ) {
                      event.preventDefault();
                      event.currentTarget.form?.requestSubmit();
                    }
                  }}
                />
                <button
                  type="button"
                  className="mb-0.5 rounded-xl p-2 text-slate-500 hover:bg-white/5 hover:text-white"
                >
                  <Smile className="size-4" />
                </button>
                <button
                  disabled={
                    (!composer.trim() &&
                      !uploads.some((item) => item.status === "ready")) ||
                    uploads.some(
                      (item) =>
                        item.status === "uploading" ||
                        item.status === "processing",
                    ) ||
                    !activeRoom ||
                    isEncryptedConversation
                  }
                  className="mb-0.5 grid size-9 place-items-center rounded-xl bg-[#68e0cf] text-[#061013] disabled:opacity-40"
                  aria-label="Send"
                >
                  <Send className="size-4" />
                </button>
              </form>
            </div>
          </div>
        </section>

        <aside className="hidden border-l border-white/8 bg-[#091419]/85 xl:flex xl:flex-col">
          <div className="flex h-16 items-center border-b border-white/8 px-4">
            <div>
              <p className="font-semibold">Details</p>
              <p className="text-xs text-slate-500">
                {currentWorkspace?.role ?? "Member"} access
              </p>
            </div>
          </div>
          <div className="flex-1 overflow-y-auto p-4">
            <div className="rounded-2xl border border-white/8 bg-white/[0.03] p-4">
              <div className="flex items-center gap-2">
                <Users className="size-4 text-[#68e0cf]" />
                <p className="text-sm font-medium">Workspace members</p>
              </div>
              <p className="mt-1 text-xs text-slate-500">
                Realtime presence across connected devices.
              </p>

              <div className="mt-4 space-y-2">
                {(presence.data?.items ?? []).map((member) => (
                  <div
                    key={member.userId}
                    className="flex items-center gap-3 rounded-xl px-2 py-2"
                  >
                    <div className="relative grid size-9 shrink-0 place-items-center rounded-xl border border-white/10 bg-white/[0.04] text-xs font-semibold">
                      {initials(member.displayName) || "?"}
                      <span
                        className={
                          "absolute -bottom-0.5 -right-0.5 size-2.5 rounded-full border-2 border-[#0b171c] " +
                          (member.status === "online"
                            ? "bg-emerald-400"
                            : member.status === "idle"
                              ? "bg-amber-400"
                              : member.status === "do-not-disturb"
                                ? "bg-rose-400"
                                : "bg-slate-600")
                        }
                        title={member.status}
                      />
                    </div>
                    <div className="min-w-0">
                      <p className="truncate text-xs font-medium text-slate-300">
                        {member.displayName}
                      </p>
                      <p className="truncate text-[10px] text-slate-600">
                        {member.customText
                          ? member.customText
                          : member.status === "offline" && member.lastSeenAt
                            ? `Last seen ${new Date(member.lastSeenAt).toLocaleString()}`
                            : member.status}
                      </p>
                    </div>
                    {member.connectedDevices > 1 && (
                      <span className="ml-auto text-[10px] text-slate-600">
                        {member.connectedDevices} devices
                      </span>
                    )}
                  </div>
                ))}
                {presence.isLoading && (
                  <div className="grid h-24 place-items-center">
                    <Loader2 className="size-4 animate-spin text-[#68e0cf]" />
                  </div>
                )}
              </div>
            </div>
          </div>
        </aside>
      </div>
      {searchOpen && (
        <div
          className="fixed inset-0 z-50 grid place-items-start bg-black/55 p-4 pt-[8vh] backdrop-blur-sm"
          role="presentation"
          onMouseDown={(event) => {
            if (event.currentTarget === event.target) setSearchOpen(false);
          }}
        >
          <section
            role="dialog"
            aria-modal="true"
            aria-label="Global search"
            className="w-full max-w-2xl overflow-hidden rounded-[28px] border border-white/10 bg-[#09151a] shadow-2xl shadow-black/50"
          >
            <div className="flex items-center gap-3 border-b border-white/8 px-4">
              <Search className="size-5 text-[#68e0cf]" />
              <input
                value={searchQuery}
                onChange={(event) => setSearchQuery(event.target.value)}
                autoFocus
                placeholder="Search messages, channels and people…"
                className="w-full bg-transparent py-4 text-base outline-none placeholder:text-slate-600"
              />
              <button
                type="button"
                onClick={() => setSearchOpen(false)}
                className="rounded-xl border border-white/8 px-3 py-1.5 text-xs text-slate-500"
              >
                Esc
              </button>
            </div>

            <div className="max-h-[65vh] overflow-y-auto p-3">
              {searchQuery.trim().length < 2 ? (
                <div className="py-12 text-center text-sm text-slate-600">
                  Type at least 2 characters to search PulseMesh.
                </div>
              ) : searchResults.isLoading ? (
                <div className="grid h-36 place-items-center">
                  <Loader2 className="size-5 animate-spin text-[#68e0cf]" />
                </div>
              ) : (
                <div className="space-y-5">
                  {(searchResults.data?.channels ?? []).length > 0 && (
                    <section>
                      <p className="mb-2 px-2 text-[11px] font-semibold uppercase tracking-[0.16em] text-slate-600">
                        Channels
                      </p>
                      <div className="space-y-1">
                        {(searchResults.data?.channels ?? []).map((channel) => (
                          <button
                            key={channel.id}
                            type="button"
                            onClick={() => {
                              setWorkspaceId(channel.workspace_id);
                              setConversationId(null);
                              setChannelId(channel.id);
                              setSearchOpen(false);
                            }}
                            className="flex w-full items-center gap-3 rounded-2xl px-3 py-2 text-left hover:bg-white/[0.04]"
                          >
                            <Hash className="size-4 text-[#68e0cf]" />
                            <span className="text-sm">{channel.name}</span>
                          </button>
                        ))}
                      </div>
                    </section>
                  )}

                  {(searchResults.data?.messages ?? []).length > 0 && (
                    <section>
                      <p className="mb-2 px-2 text-[11px] font-semibold uppercase tracking-[0.16em] text-slate-600">
                        Messages
                      </p>
                      <div className="space-y-1">
                        {(searchResults.data?.messages ?? []).map((message) => (
                          <button
                            key={message.id}
                            type="button"
                            onClick={() => {
                              if (message.channel_id) {
                                setConversationId(null);
                                setChannelId(message.channel_id);
                              } else if (message.conversation_id) {
                                setChannelId(null);
                                setConversationId(message.conversation_id);
                              }
                              setSearchOpen(false);
                            }}
                            className="w-full rounded-2xl px-3 py-2 text-left hover:bg-white/[0.04]"
                          >
                            <div className="flex items-center gap-2 text-xs">
                              <span className="font-medium text-slate-300">
                                {message.display_name}
                              </span>
                              <span className="text-slate-600">
                                @{message.username}
                              </span>
                            </div>
                            <p className="mt-1 line-clamp-2 text-sm text-slate-400">
                              {message.body}
                            </p>
                          </button>
                        ))}
                      </div>
                    </section>
                  )}

                  {(searchResults.data?.users ?? []).length > 0 && (
                    <section>
                      <p className="mb-2 px-2 text-[11px] font-semibold uppercase tracking-[0.16em] text-slate-600">
                        People
                      </p>
                      <div className="space-y-1">
                        {(searchResults.data?.users ?? []).map((user) => (
                          <button
                            key={user.id}
                            type="button"
                            onClick={() => {
                              setSelectedMemberIds([user.id]);
                              setUserSearch(user.display_name);
                              setNewConversationOpen(true);
                              setSearchOpen(false);
                            }}
                            className="flex w-full items-center gap-3 rounded-2xl px-3 py-2 text-left hover:bg-white/[0.04]"
                          >
                            <div className="grid size-9 place-items-center rounded-xl border border-white/10 bg-white/[0.04] text-xs font-semibold">
                              {initials(user.display_name) || "?"}
                            </div>
                            <div>
                              <p className="text-sm font-medium">
                                {user.display_name}
                              </p>
                              <p className="text-xs text-slate-600">
                                @{user.username}
                              </p>
                            </div>
                          </button>
                        ))}
                      </div>
                    </section>
                  )}

                  {!searchResults.data?.channels.length &&
                    !searchResults.data?.messages.length &&
                    !searchResults.data?.users.length && (
                      <div className="py-12 text-center text-sm text-slate-600">
                        No results found.
                      </div>
                    )}
                </div>
              )}
            </div>
          </section>
        </div>
      )}

      {notificationsOpen && (
        <div
          className="fixed inset-0 z-50 flex justify-end bg-black/40 backdrop-blur-[2px]"
          role="presentation"
          onMouseDown={(event) => {
            if (event.currentTarget === event.target)
              setNotificationsOpen(false);
          }}
        >
          <aside
            role="dialog"
            aria-modal="true"
            aria-label="Notifications"
            className="flex h-full w-full max-w-md flex-col border-l border-white/10 bg-[#09151a] shadow-2xl shadow-black/40"
          >
            <div className="flex items-center justify-between border-b border-white/8 px-5 py-4">
              <div>
                <p className="text-xs uppercase tracking-[0.16em] text-[#68e0cf]">
                  Activity
                </p>
                <h2 className="mt-1 text-lg font-semibold">Notifications</h2>
              </div>
              <button
                type="button"
                onClick={() => markAllNotificationsRead.mutate()}
                className="rounded-xl border border-white/10 px-3 py-1.5 text-xs text-slate-400 hover:text-white"
              >
                Mark all read
              </button>
            </div>

            <div className="flex-1 overflow-y-auto p-3">
              {notifications.isLoading ? (
                <div className="grid h-40 place-items-center">
                  <Loader2 className="size-5 animate-spin text-[#68e0cf]" />
                </div>
              ) : (notifications.data?.items ?? []).length ? (
                <div className="space-y-1">
                  {(notifications.data?.items ?? []).map((notification) => (
                    <button
                      key={notification.id}
                      type="button"
                      onClick={() => {
                        if (!notification.read_at) {
                          markNotificationRead.mutate(notification.id);
                        }
                        const payload = notification.payload;
                        if (typeof payload.channelId === "string") {
                          if (typeof payload.workspaceId === "string") {
                            setWorkspaceId(payload.workspaceId);
                          }
                          setConversationId(null);
                          setChannelId(payload.channelId);
                        } else if (typeof payload.conversationId === "string") {
                          setChannelId(null);
                          setConversationId(payload.conversationId);
                        }
                        setNotificationsOpen(false);
                      }}
                      className={
                        "w-full rounded-2xl border px-4 py-3 text-left transition " +
                        (notification.read_at
                          ? "border-transparent text-slate-500 hover:bg-white/[0.025]"
                          : "border-[#68e0cf]/10 bg-[#68e0cf]/[0.045] text-slate-300")
                      }
                    >
                      <div className="flex items-center gap-2">
                        <span className="text-xs font-semibold uppercase tracking-[0.12em] text-[#68e0cf]">
                          {notification.kind}
                        </span>
                        {!notification.read_at && (
                          <span className="size-1.5 rounded-full bg-[#68e0cf]" />
                        )}
                        <span className="ml-auto text-[10px] text-slate-600">
                          {new Date(notification.created_at).toLocaleString()}
                        </span>
                      </div>
                      <p className="mt-2 line-clamp-3 text-sm leading-5">
                        {typeof notification.payload.preview === "string"
                          ? notification.payload.preview
                          : "PulseMesh activity update"}
                      </p>
                    </button>
                  ))}
                </div>
              ) : (
                <div className="py-16 text-center">
                  <Bell className="mx-auto size-6 text-slate-700" />
                  <p className="mt-3 text-sm text-slate-600">
                    No notifications yet.
                  </p>
                </div>
              )}
            </div>

            <div className="border-t border-white/8 p-4">
              <button
                type="button"
                onClick={() => setNotificationsOpen(false)}
                className="w-full rounded-2xl border border-white/10 px-4 py-2.5 text-sm text-slate-400 hover:text-white"
              >
                Close
              </button>
            </div>
          </aside>
        </div>
      )}

      {activeThread && (
        <div
          className="fixed inset-0 z-40 flex justify-end bg-black/40 backdrop-blur-[2px]"
          role="presentation"
          onMouseDown={(event) => {
            if (event.currentTarget === event.target) setActiveThread(null);
          }}
        >
          <aside
            role="dialog"
            aria-modal="true"
            aria-label="Message thread"
            className="flex h-full w-full max-w-md flex-col border-l border-white/10 bg-[#09151a] shadow-2xl shadow-black/40"
          >
            <div className="flex items-center justify-between border-b border-white/8 px-5 py-4">
              <div>
                <p className="text-xs uppercase tracking-[0.16em] text-[#68e0cf]">
                  Thread
                </p>
                <h2 className="mt-1 font-semibold">
                  {activeThread.sender.displayName}
                </h2>
              </div>
              <button
                type="button"
                onClick={() => setActiveThread(null)}
                className="rounded-xl border border-white/10 px-3 py-1.5 text-sm text-slate-400 hover:text-white"
              >
                Close
              </button>
            </div>

            <div className="border-b border-white/8 p-5">
              <p className="whitespace-pre-wrap text-sm leading-6 text-slate-300">
                {activeThread.body}
              </p>
            </div>

            <div className="flex-1 overflow-y-auto p-5">
              {thread.isLoading ? (
                <div className="grid h-32 place-items-center">
                  <Loader2 className="size-5 animate-spin text-[#68e0cf]" />
                </div>
              ) : (thread.data?.items ?? []).length ? (
                <div className="space-y-5">
                  {(thread.data?.items ?? []).map((reply) => (
                    <div key={reply.id} className="flex gap-3">
                      <div className="grid size-9 shrink-0 place-items-center rounded-xl border border-white/10 bg-white/[0.04] text-xs font-semibold">
                        {initials(reply.display_name) || "?"}
                      </div>
                      <div className="min-w-0">
                        <div className="flex items-baseline gap-2">
                          <span className="text-sm font-medium">
                            {reply.display_name}
                          </span>
                          <span className="text-[10px] text-slate-600">
                            {new Date(reply.created_at).toLocaleTimeString([], {
                              hour: "2-digit",
                              minute: "2-digit",
                            })}
                          </span>
                        </div>
                        <p className="mt-1 whitespace-pre-wrap text-sm leading-6 text-slate-300">
                          {reply.body}
                        </p>
                      </div>
                    </div>
                  ))}
                </div>
              ) : (
                <p className="py-10 text-center text-sm text-slate-600">
                  No replies yet.
                </p>
              )}
            </div>

            <form
              className="border-t border-white/8 p-4"
              onSubmit={(event) => {
                event.preventDefault();
                sendThreadReply.mutate();
              }}
            >
              <div className="flex items-end gap-2 rounded-2xl border border-white/10 bg-white/[0.035] p-2">
                <textarea
                  value={threadComposer}
                  onChange={(event) => setThreadComposer(event.target.value)}
                  rows={2}
                  placeholder="Reply in thread…"
                  className="max-h-32 min-h-12 flex-1 resize-none bg-transparent px-2 py-2 text-sm outline-none"
                />
                <button
                  disabled={!threadComposer.trim() || sendThreadReply.isPending}
                  className="grid size-9 place-items-center rounded-xl bg-[#68e0cf] text-[#061013] disabled:opacity-40"
                  aria-label="Send thread reply"
                >
                  {sendThreadReply.isPending ? (
                    <Loader2 className="size-4 animate-spin" />
                  ) : (
                    <Send className="size-4" />
                  )}
                </button>
              </div>
            </form>
          </aside>
        </div>
      )}

      {newConversationOpen && (
        <div
          className="fixed inset-0 z-50 grid place-items-center bg-black/60 p-4 backdrop-blur-sm"
          role="presentation"
          onMouseDown={(event) => {
            if (event.currentTarget === event.target) {
              setNewConversationOpen(false);
            }
          }}
        >
          <section
            role="dialog"
            aria-modal="true"
            aria-labelledby="new-conversation-title"
            className="w-full max-w-lg rounded-[28px] border border-white/10 bg-[#0a171d] p-5 shadow-2xl shadow-black/50"
          >
            <div className="flex items-start justify-between gap-4">
              <div>
                <p className="text-xs font-semibold uppercase tracking-[0.18em] text-[#68e0cf]">
                  New conversation
                </p>
                <h2
                  id="new-conversation-title"
                  className="mt-1 text-xl font-semibold"
                >
                  Start a DM or group
                </h2>
              </div>
              <button
                type="button"
                onClick={() => setNewConversationOpen(false)}
                className="rounded-xl border border-white/8 px-3 py-1.5 text-sm text-slate-400 hover:text-white"
              >
                Close
              </button>
            </div>

            <label className="mt-5 block">
              <span className="mb-1.5 block text-xs text-slate-400">
                Find people
              </span>
              <div className="flex items-center gap-2 rounded-2xl border border-white/10 bg-white/[0.035] px-3">
                <Search className="size-4 text-slate-500" />
                <input
                  value={userSearch}
                  onChange={(event) => setUserSearch(event.target.value)}
                  className="w-full bg-transparent py-3 text-sm outline-none"
                  placeholder="Search by name or username"
                  autoFocus
                />
              </div>
            </label>

            <div className="mt-3 max-h-52 space-y-1 overflow-y-auto">
              {userSearch.trim().length < 2 ? (
                <p className="px-2 py-5 text-center text-sm text-slate-600">
                  Type at least 2 characters.
                </p>
              ) : userSearchResults.isLoading ? (
                <div className="grid h-20 place-items-center">
                  <Loader2 className="size-5 animate-spin text-[#68e0cf]" />
                </div>
              ) : (userSearchResults.data?.users ?? []).length ? (
                (userSearchResults.data?.users ?? []).map((user) => {
                  const selected = selectedMemberIds.includes(user.id);
                  return (
                    <button
                      key={user.id}
                      type="button"
                      onClick={() =>
                        setSelectedMemberIds((current) =>
                          selected
                            ? current.filter((id) => id !== user.id)
                            : [...current, user.id],
                        )
                      }
                      className={
                        "flex w-full items-center gap-3 rounded-2xl px-3 py-2 text-left transition " +
                        (selected
                          ? "bg-[#68e0cf]/10 text-white"
                          : "hover:bg-white/[0.04]")
                      }
                    >
                      <div className="grid size-9 place-items-center rounded-xl border border-white/10 bg-white/[0.04] text-xs font-semibold">
                        {initials(user.display_name) || "?"}
                      </div>
                      <div className="min-w-0">
                        <p className="truncate text-sm font-medium">
                          {user.display_name}
                        </p>
                        <p className="truncate text-xs text-slate-500">
                          @{user.username}
                        </p>
                      </div>
                      <span className="ml-auto text-xs text-[#68e0cf]">
                        {selected ? "Selected" : "Add"}
                      </span>
                    </button>
                  );
                })
              ) : (
                <p className="px-2 py-5 text-center text-sm text-slate-600">
                  No matching workspace members.
                </p>
              )}
            </div>

            {selectedMemberIds.length > 1 && (
              <label className="mt-4 block">
                <span className="mb-1.5 block text-xs text-slate-400">
                  Group name
                </span>
                <input
                  value={groupName}
                  onChange={(event) => setGroupName(event.target.value)}
                  maxLength={100}
                  className="w-full rounded-2xl border border-white/10 bg-white/[0.035] px-4 py-3 text-sm outline-none focus:border-[#68e0cf]/50"
                  placeholder="Optional group name"
                />
              </label>
            )}

            {createConversation.error && (
              <div className="mt-4 rounded-2xl border border-rose-400/20 bg-rose-400/10 px-4 py-3 text-sm text-rose-200">
                {createConversation.error instanceof Error
                  ? createConversation.error.message
                  : "Could not create conversation"}
              </div>
            )}

            <div className="mt-5 flex items-center justify-between gap-3">
              <p className="text-xs text-slate-500">
                {selectedMemberIds.length === 0
                  ? "No people selected"
                  : selectedMemberIds.length === 1
                    ? "Direct message"
                    : `${selectedMemberIds.length} people · Group conversation`}
              </p>
              <button
                type="button"
                disabled={
                  !selectedMemberIds.length || createConversation.isPending
                }
                onClick={() => createConversation.mutate()}
                className="flex items-center gap-2 rounded-2xl bg-[#68e0cf] px-4 py-2.5 text-sm font-semibold text-[#061013] disabled:opacity-40"
              >
                {createConversation.isPending && (
                  <Loader2 className="size-4 animate-spin" />
                )}
                Start conversation
              </button>
            </div>
          </section>
        </div>
      )}
    </main>
  );
}

function PulseMeshClientInner() {
  const [token, setToken] = useState<string | null>(null);
  const [bootstrapping, setBootstrapping] = useState(true);
  const refreshPromiseRef = useRef<Promise<string | null> | null>(null);

  const refreshSession = useCallback(async (): Promise<string | null> => {
    if (refreshPromiseRef.current) return refreshPromiseRef.current;

    const pending = request<{ accessToken: string }>("/auth/refresh", null, {
      method: "POST",
      body: "{}",
    })
      .then((result) => {
        setToken(result.accessToken);
        return result.accessToken;
      })
      .catch(() => {
        setToken(null);
        return null;
      })
      .finally(() => {
        refreshPromiseRef.current = null;
      });

    refreshPromiseRef.current = pending;
    return pending;
  }, []);

  useEffect(() => {
    setAccessTokenRefresher(refreshSession);
    return () => setAccessTokenRefresher(null);
  }, [refreshSession]);

  useEffect(() => {
    let cancelled = false;
    request<{ accessToken: string }>("/auth/refresh", null, {
      method: "POST",
      body: "{}",
    })
      .then((result) => {
        if (!cancelled) setToken(result.accessToken);
      })
      .catch(() => {
        if (!cancelled) setToken(null);
      })
      .finally(() => {
        if (!cancelled) setBootstrapping(false);
      });

    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    if (!token) return;

    const expiresAt = tokenExpiresAt(token);
    const refreshAt = expiresAt
      ? Math.max(expiresAt - Date.now() - 60_000, 5_000)
      : 10 * 60_000;

    const timer = window.setTimeout(() => {
      void refreshSession();
    }, refreshAt);

    const refreshIfNeeded = () => {
      const currentExpiry = tokenExpiresAt(token);
      if (!currentExpiry || currentExpiry - Date.now() <= 90_000) {
        void refreshSession();
      }
    };

    const onVisibility = () => {
      if (document.visibilityState === "visible") refreshIfNeeded();
    };

    window.addEventListener("focus", refreshIfNeeded);
    document.addEventListener("visibilitychange", onVisibility);

    return () => {
      window.clearTimeout(timer);
      window.removeEventListener("focus", refreshIfNeeded);
      document.removeEventListener("visibilitychange", onVisibility);
    };
  }, [refreshSession, token]);

  if (bootstrapping) {
    return (
      <main className="grid min-h-screen place-items-center">
        <div className="flex items-center gap-3 text-sm text-slate-400">
          <Loader2 className="size-5 animate-spin text-[#68e0cf]" />
          Restoring session…
        </div>
      </main>
    );
  }

  if (!token) {
    return <AuthScreen onAuthenticated={setToken} />;
  }

  return <WorkspaceApp token={token} onLoggedOut={() => setToken(null)} />;
}

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 15_000,
      refetchOnWindowFocus: false,
      retry: 1,
    },
  },
});

export default function PulseMeshClient() {
  return (
    <QueryClientProvider client={queryClient}>
      <PulseMeshClientInner />
    </QueryClientProvider>
  );
}
