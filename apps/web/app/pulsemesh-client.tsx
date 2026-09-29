'use client';

import {
  QueryClient,
  QueryClientProvider,
  useMutation,
  useQuery,
  useQueryClient
} from '@tanstack/react-query';
import {
  Bell,
  ChevronDown,
  Hash,
  Loader2,
  LogOut,
  Plus,
  Search,
  Send,
  Smile,
  Sparkles,
  Users,
  Volume2,
  Wifi,
  WifiOff
} from 'lucide-react';
import {
  FormEvent,
  useEffect,
  useMemo,
  useRef,
  useState
} from 'react';

const API_URL =
  process.env.NEXT_PUBLIC_API_URL ?? 'http://localhost:4000';
const WS_URL =
  process.env.NEXT_PUBLIC_WS_URL ?? 'ws://localhost:4000/realtime';

type ApiError = {
  error?: { code?: string; message?: string; requestId?: string };
};

type Workspace = {
  id: string;
  name: string;
  slug: string;
  avatar_url: string | null;
  description: string | null;
  role: string;
};

type Channel = {
  id: string;
  name: string;
  topic: string | null;
  kind: 'text' | 'voice';
  visibility: string;
  position: number;
};

type Message = {
  id: string;
  clientMessageId: string | null;
  channelId: string;
  body: string;
  createdAt: string;
  editedAt: string | null;
  sender: {
    id: string;
    username: string;
    displayName: string;
    avatarUrl: string | null;
  };
  optimistic?: boolean;
  failed?: boolean;
};

type Page<T> = { items: T[]; nextCursor: string | null };

async function request<T>(
  path: string,
  accessToken?: string | null,
  init: RequestInit = {}
): Promise<T> {
  const response = await fetch(API_URL + path, {
    ...init,
    credentials: 'include',
    headers: {
      'content-type': 'application/json',
      'x-pulsemesh-client': 'web',
      ...(accessToken
        ? { authorization: 'Bearer ' + accessToken }
        : {}),
      ...init.headers
    }
  });

  if (!response.ok) {
    let body: ApiError = {};
    try {
      body = (await response.json()) as ApiError;
    } catch {
      // Keep the normalized fallback below.
    }
    throw new Error(
      body.error?.message ??
        `Request failed with status ${response.status}`
    );
  }

  return (await response.json()) as T;
}

function initials(name: string) {
  return name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase())
    .join('');
}

function AuthScreen({
  onAuthenticated
}: {
  onAuthenticated: (token: string) => void;
}) {
  const [mode, setMode] = useState<'login' | 'register'>('login');
  const [error, setError] = useState<string | null>(null);

  const auth = useMutation({
    mutationFn: async (form: FormData) => {
      const payload =
        mode === 'login'
          ? {
              email: String(form.get('email') ?? ''),
              password: String(form.get('password') ?? ''),
              device: 'PulseMesh Web',
              browser: navigator.userAgent.slice(0, 100)
            }
          : {
              email: String(form.get('email') ?? ''),
              password: String(form.get('password') ?? ''),
              username: String(form.get('username') ?? ''),
              displayName: String(form.get('displayName') ?? ''),
              device: 'PulseMesh Web',
              browser: navigator.userAgent.slice(0, 100)
            };

      return request<{ accessToken: string }>(
        mode === 'login' ? '/auth/login' : '/auth/register',
        null,
        { method: 'POST', body: JSON.stringify(payload) }
      );
    },
    onSuccess: ({ accessToken }) => {
      setError(null);
      onAuthenticated(accessToken);
    },
    onError: (value) => {
      setError(
        value instanceof Error ? value.message : 'Authentication failed'
      );
    }
  });

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError(null);
    auth.mutate(new FormData(event.currentTarget));
  }

  return (
    <main className="grid min-h-screen place-items-center p-6">
      <div className="grid w-full max-w-5xl overflow-hidden rounded-[32px] border border-white/10 bg-[#09151a]/90 shadow-2xl shadow-black/30 lg:grid-cols-[1.2fr_0.8fr]">
        <section className="hidden min-h-[620px] flex-col justify-between border-r border-white/8 bg-[radial-gradient(circle_at_20%_10%,rgba(104,224,207,.18),transparent_24rem),linear-gradient(145deg,#071116,#0b1f27)] p-10 lg:flex">
          <div className="grid size-14 place-items-center rounded-2xl bg-[linear-gradient(135deg,#68e0cf,#73a7ff)] text-xl font-black text-[#061013]">
            P
          </div>
          <div>
            <p className="mb-4 text-xs font-semibold uppercase tracking-[0.2em] text-[#7fe9dc]">
              PulseMesh
            </p>
            <h1 className="max-w-lg text-4xl font-semibold leading-tight">
              Realtime collaboration without losing engineering discipline.
            </h1>
            <p className="mt-5 max-w-xl text-sm leading-7 text-slate-400">
              Channels, direct messaging, presence, media sessions and
              offline recovery on one production-oriented realtime core.
            </p>
          </div>
          <div className="flex gap-5 text-xs text-slate-500">
            <span>WebSocket recovery</span>
            <span>WebRTC</span>
            <span>Offline sync</span>
          </div>
        </section>

        <section className="p-7 sm:p-10">
          <div className="mb-8 lg:hidden">
            <div className="grid size-12 place-items-center rounded-2xl bg-[linear-gradient(135deg,#68e0cf,#73a7ff)] font-black text-[#061013]">
              P
            </div>
          </div>
          <p className="text-xs font-semibold uppercase tracking-[0.2em] text-[#68e0cf]">
            Welcome to PulseMesh
          </p>
          <h2 className="mt-2 text-2xl font-semibold">
            {mode === 'login' ? 'Sign in' : 'Create your account'}
          </h2>
          <p className="mt-2 text-sm text-slate-500">
            Your refresh session is kept in an HttpOnly cookie. Access tokens
            stay in memory.
          </p>

          <div className="mt-7 grid grid-cols-2 rounded-2xl border border-white/8 bg-white/[0.025] p-1">
            {(['login', 'register'] as const).map((item) => (
              <button
                key={item}
                type="button"
                onClick={() => {
                  setMode(item);
                  setError(null);
                }}
                className={
                  'rounded-xl px-3 py-2 text-sm transition ' +
                  (mode === item
                    ? 'bg-white/[0.08] text-white'
                    : 'text-slate-500 hover:text-slate-300')
                }
              >
                {item === 'login' ? 'Sign in' : 'Register'}
              </button>
            ))}
          </div>

          <form className="mt-6 space-y-4" onSubmit={submit}>
            {mode === 'register' && (
              <>
                <label className="block">
                  <span className="mb-1.5 block text-xs text-slate-400">
                    Display name
                  </span>
                  <input
                    required
                    name="displayName"
                    maxLength={80}
                    className="w-full rounded-2xl border border-white/10 bg-white/[0.035] px-4 py-3 outline-none transition focus:border-[#68e0cf]/50"
                    placeholder="Mohammed"
                  />
                </label>
                <label className="block">
                  <span className="mb-1.5 block text-xs text-slate-400">
                    Username
                  </span>
                  <input
                    required
                    name="username"
                    minLength={3}
                    maxLength={32}
                    pattern="[A-Za-z0-9_.-]+"
                    className="w-full rounded-2xl border border-white/10 bg-white/[0.035] px-4 py-3 outline-none transition focus:border-[#68e0cf]/50"
                    placeholder="mohammed"
                  />
                </label>
              </>
            )}
            <label className="block">
              <span className="mb-1.5 block text-xs text-slate-400">
                Email
              </span>
              <input
                required
                type="email"
                name="email"
                autoComplete="email"
                className="w-full rounded-2xl border border-white/10 bg-white/[0.035] px-4 py-3 outline-none transition focus:border-[#68e0cf]/50"
                placeholder="you@example.com"
              />
            </label>
            <label className="block">
              <span className="mb-1.5 block text-xs text-slate-400">
                Password
              </span>
              <input
                required
                type="password"
                name="password"
                minLength={12}
                maxLength={128}
                autoComplete={
                  mode === 'login'
                    ? 'current-password'
                    : 'new-password'
                }
                className="w-full rounded-2xl border border-white/10 bg-white/[0.035] px-4 py-3 outline-none transition focus:border-[#68e0cf]/50"
                placeholder="At least 12 characters"
              />
            </label>

            {error && (
              <div className="rounded-2xl border border-rose-400/20 bg-rose-400/10 px-4 py-3 text-sm text-rose-200">
                {error}
              </div>
            )}

            <button
              disabled={auth.isPending}
              className="flex w-full items-center justify-center gap-2 rounded-2xl bg-[#68e0cf] px-4 py-3 font-semibold text-[#061013] transition hover:brightness-105 disabled:opacity-60"
            >
              {auth.isPending && (
                <Loader2 className="size-4 animate-spin" />
              )}
              {mode === 'login' ? 'Sign in' : 'Create account'}
            </button>
          </form>
        </section>
      </div>
    </main>
  );
}

function WorkspaceApp({
  token,
  onLoggedOut
}: {
  token: string;
  onLoggedOut: () => void;
}) {
  const queryClient = useQueryClient();
  const [workspaceId, setWorkspaceId] = useState<string | null>(null);
  const [channelId, setChannelId] = useState<string | null>(null);
  const [composer, setComposer] = useState('');
  const [socketState, setSocketState] = useState<
    'connecting' | 'ready' | 'reconnecting'
  >('connecting');
  const [typing, setTyping] = useState(false);
  const socketRef = useRef<WebSocket | null>(null);
  const retryRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const reconnectAttempt = useRef(0);

  const workspaces = useQuery({
    queryKey: ['workspaces'],
    queryFn: () =>
      request<{ items: Workspace[] }>('/workspaces', token)
  });

  useEffect(() => {
    const first = workspaces.data?.items[0];
    if (!workspaceId && first) setWorkspaceId(first.id);
  }, [workspaceId, workspaces.data]);

  const channels = useQuery({
    queryKey: ['channels', workspaceId],
    enabled: Boolean(workspaceId),
    queryFn: () =>
      request<{ items: Channel[] }>(
        `/workspaces/${workspaceId}/channels`,
        token
      )
  });

  useEffect(() => {
    const textChannels =
      channels.data?.items.filter((item) => item.kind === 'text') ?? [];
    if (
      textChannels.length > 0 &&
      (!channelId ||
        !textChannels.some((item) => item.id === channelId))
    ) {
      setChannelId(textChannels[0]!.id);
    }
  }, [channelId, channels.data]);

  const messages = useQuery({
    queryKey: ['messages', channelId],
    enabled: Boolean(channelId),
    queryFn: () =>
      request<Page<Message>>(
        `/channels/${channelId}/messages?limit=50`,
        token
      )
  });

  useEffect(() => {
    if (!channelId) return;

    let cancelled = false;

    const connect = async () => {
      setSocketState(
        reconnectAttempt.current > 0 ? 'reconnecting' : 'connecting'
      );
      try {
        const { ticket } = await request<{ ticket: string }>(
          '/realtime/ticket',
          token,
          { method: 'POST', body: '{}' }
        );
        if (cancelled) return;

        const url = new URL(WS_URL);
        url.searchParams.set('ticket', ticket);
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

          if (event.type === 'session.ready') {
            const sequence = Number(
              sessionStorage.getItem('pulsemesh:last-sequence') ?? '0'
            );
            socket.send(
              JSON.stringify({
                type: 'session.resume',
                lastSequence: Number.isFinite(sequence) ? sequence : 0,
                rooms: [`channel:${channelId}`]
              })
            );
            return;
          }

          if (event.type === 'session.resumed') {
            socket.send(
              JSON.stringify({
                type: 'room.subscribe',
                room: `channel:${channelId}`
              })
            );
            socket.send(
              JSON.stringify({
                type: 'view.active',
                room: `channel:${channelId}`
              })
            );
            setSocketState('ready');
            if (event.truncated) {
              void queryClient.invalidateQueries({
                queryKey: ['messages', channelId]
              });
            }
            return;
          }

          if (typeof event.sequence === 'number') {
            sessionStorage.setItem(
              'pulsemesh:last-sequence',
              String(event.sequence)
            );
          }

          if (
            event.room === `channel:${channelId}` &&
            event.type.startsWith('message.')
          ) {
            void queryClient.invalidateQueries({
              queryKey: ['messages', channelId]
            });
          }

          if (
            event.room === `channel:${channelId}` &&
            event.type === 'typing.started'
          ) {
            setTyping(true);
          }
          if (
            event.room === `channel:${channelId}` &&
            event.type === 'typing.stopped'
          ) {
            setTyping(false);
          }
        };

        socket.onclose = () => {
          if (cancelled) return;
          setSocketState('reconnecting');
          reconnectAttempt.current += 1;
          const delay = Math.min(
            1000 * 2 ** Math.min(reconnectAttempt.current, 5),
            30000
          );
          retryRef.current = setTimeout(connect, delay);
        };

        socket.onerror = () => socket.close();
      } catch {
        if (cancelled) return;
        setSocketState('reconnecting');
        reconnectAttempt.current += 1;
        retryRef.current = setTimeout(
          connect,
          Math.min(1000 * 2 ** reconnectAttempt.current, 30000)
        );
      }
    };

    void connect();

    return () => {
      cancelled = true;
      if (retryRef.current) clearTimeout(retryRef.current);
      socketRef.current?.close(1000, 'Channel changed');
      socketRef.current = null;
      setTyping(false);
    };
  }, [channelId, queryClient, token]);

  const sendMessage = useMutation({
    mutationFn: async ({
      body,
      clientMessageId
    }: {
      body: string;
      clientMessageId: string;
    }) => {
      if (!channelId) throw new Error('No channel selected');
      return request(
        `/channels/${channelId}/messages`,
        token,
        {
          method: 'POST',
          body: JSON.stringify({
            body,
            clientMessageId,
            attachmentIds: []
          })
        }
      );
    },
    onMutate: async ({ body, clientMessageId }) => {
      if (!channelId) return;
      const key = ['messages', channelId] as const;
      await queryClient.cancelQueries({ queryKey: key });
      const previous = queryClient.getQueryData<Page<Message>>(key);
      const optimistic: Message = {
        id: clientMessageId,
        clientMessageId,
        channelId,
        body,
        createdAt: new Date().toISOString(),
        editedAt: null,
        optimistic: true,
        sender: {
          id: 'self',
          username: 'you',
          displayName: 'You',
          avatarUrl: null
        }
      };
      queryClient.setQueryData<Page<Message>>(key, {
        items: [optimistic, ...(previous?.items ?? [])],
        nextCursor: previous?.nextCursor ?? null
      });
      return { previous, key };
    },
    onError: (_error, _variables, context) => {
      if (context?.key) {
        queryClient.setQueryData(context.key, context.previous);
      }
    },
    onSettled: () => {
      if (channelId) {
        void queryClient.invalidateQueries({
          queryKey: ['messages', channelId]
        });
      }
    }
  });

  const logout = useMutation({
    mutationFn: () =>
      request('/auth/logout', token, {
        method: 'POST',
        body: '{}'
      }),
    onSettled: onLoggedOut
  });

  const currentWorkspace = workspaces.data?.items.find(
    (item) => item.id === workspaceId
  );
  const currentChannel = channels.data?.items.find(
    (item) => item.id === channelId
  );
  const textChannels =
    channels.data?.items.filter((item) => item.kind === 'text') ?? [];
  const voiceChannels =
    channels.data?.items.filter((item) => item.kind === 'voice') ?? [];
  const orderedMessages = useMemo(
    () => [...(messages.data?.items ?? [])].reverse(),
    [messages.data]
  );

  function submitMessage(event: FormEvent) {
    event.preventDefault();
    const body = composer.trim();
    if (!body || !channelId || sendMessage.isPending) return;
    setComposer('');
    sendMessage.mutate({
      body,
      clientMessageId: crypto.randomUUID()
    });
    socketRef.current?.send(
      JSON.stringify({
        type: 'typing.stopped',
        room: `channel:${channelId}`
      })
    );
  }

  function onComposerChange(value: string) {
    setComposer(value);
    if (
      channelId &&
      socketRef.current?.readyState === WebSocket.OPEN
    ) {
      socketRef.current.send(
        JSON.stringify({
          type: value
            ? 'typing.started'
            : 'typing.stopped',
          room: `channel:${channelId}`
        })
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

  if (!workspaces.data?.items.length) {
    return (
      <main className="grid min-h-screen place-items-center p-6">
        <div className="max-w-lg rounded-[28px] border border-white/10 bg-[#09151a]/90 p-8 text-center">
          <Sparkles className="mx-auto size-7 text-[#68e0cf]" />
          <h1 className="mt-4 text-2xl font-semibold">
            Your PulseMesh account is ready
          </h1>
          <p className="mt-3 text-sm leading-6 text-slate-400">
            Create a workspace through the API or seed the development
            workspace, then this client will load it immediately.
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
          {workspaces.data.items.map((workspace) => (
            <button
              key={workspace.id}
              onClick={() => {
                setWorkspaceId(workspace.id);
                setChannelId(null);
              }}
              className={
                'grid size-11 place-items-center rounded-2xl border text-sm font-semibold transition ' +
                (workspace.id === workspaceId
                  ? 'border-[#68e0cf]/35 bg-[#68e0cf]/12 text-[#9af5e8]'
                  : 'border-white/8 bg-white/[0.035] text-slate-400 hover:bg-white/[0.07]')
              }
              aria-label={workspace.name}
            >
              {initials(workspace.name) || 'W'}
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
                  {currentWorkspace?.name ?? 'PulseMesh'}
                </span>
                <ChevronDown className="size-4 shrink-0 text-slate-500" />
              </button>
            </div>
          </div>
          <div className="p-3">
            <button className="flex w-full items-center gap-2 rounded-xl border border-white/8 bg-white/[0.035] px-3 py-2 text-left text-sm text-slate-400">
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
                  onClick={() => setChannelId(channel.id)}
                  className={
                    'flex w-full items-center gap-2 rounded-xl px-2.5 py-2 text-sm ' +
                    (channel.id === channelId
                      ? 'bg-[linear-gradient(90deg,rgba(104,224,207,.11),rgba(115,167,255,.05))] text-white'
                      : 'text-slate-400 hover:bg-white/[0.04] hover:text-slate-200')
                  }
                >
                  <Hash className="size-4 opacity-60" />
                  <span className="truncate">{channel.name}</span>
                </button>
              ))}
            </div>
            <div className="mb-2 mt-6 flex items-center justify-between px-2 text-[11px] font-semibold uppercase tracking-[0.16em] text-slate-500">
              Voice
              <Plus className="size-3.5" />
            </div>
            {voiceChannels.length ? (
              voiceChannels.map((channel) => (
                <button
                  key={channel.id}
                  className="flex w-full items-center gap-2 rounded-xl px-2.5 py-2 text-sm text-slate-400 hover:bg-white/[0.04]"
                >
                  <Volume2 className="size-4" />
                  {channel.name}
                </button>
              ))
            ) : (
              <p className="px-2 text-xs text-slate-600">
                No voice rooms yet
              </p>
            )}
          </nav>
        </aside>

        <section className="flex min-w-0 flex-col bg-[#0b171c]/70">
          <header className="flex h-16 items-center gap-3 border-b border-white/8 px-4 md:px-5">
            <div className="grid size-9 place-items-center rounded-xl bg-white/[0.04]">
              <Hash className="size-4 text-[#82e9dc]" />
            </div>
            <div className="min-w-0">
              <h1 className="font-semibold">
                {currentChannel?.name ?? 'Select a channel'}
              </h1>
              <p className="truncate text-xs text-slate-500">
                {currentChannel?.topic ?? 'Realtime team conversation'}
              </p>
            </div>
            <div className="ml-auto flex items-center gap-1">
              <div
                className="mr-2 flex items-center gap-1.5 text-[11px] text-slate-500"
                title={socketState}
              >
                {socketState === 'ready' ? (
                  <Wifi className="size-3.5 text-emerald-400" />
                ) : (
                  <WifiOff className="size-3.5 text-amber-400" />
                )}
                {socketState}
              </div>
              <button className="rounded-xl p-2 text-slate-500 hover:bg-white/5 hover:text-white">
                <Search className="size-4" />
              </button>
              <button className="rounded-xl p-2 text-slate-500 hover:bg-white/5 hover:text-white">
                <Bell className="size-4" />
              </button>
            </div>
          </header>

          <div className="relative flex-1 overflow-y-auto px-4 py-6 md:px-7">
            <div className="mx-auto max-w-3xl">
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
                        'flex gap-3 ' +
                        (message.optimistic ? 'opacity-60' : '')
                      }
                    >
                      <div className="grid size-10 shrink-0 place-items-center rounded-2xl border border-white/10 bg-white/[0.05] text-xs font-semibold">
                        {initials(message.sender.displayName) || '?'}
                      </div>
                      <div className="min-w-0 flex-1">
                        <div className="flex items-baseline gap-2">
                          <h3 className="text-sm font-semibold">
                            {message.sender.displayName}
                          </h3>
                          <span className="text-[11px] text-slate-600">
                            {new Date(message.createdAt).toLocaleTimeString(
                              [],
                              { hour: '2-digit', minute: '2-digit' }
                            )}
                          </span>
                          {message.editedAt && (
                            <span className="text-[10px] text-slate-600">
                              edited
                            </span>
                          )}
                        </div>
                        <p className="mt-1 whitespace-pre-wrap break-words text-[15px] leading-6 text-slate-300">
                          {message.body}
                        </p>
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
                    Messages sent here are persisted in PostgreSQL and
                    delivered over WebSockets.
                  </p>
                </div>
              )}
            </div>
          </div>

          <div className="px-4 pb-4 md:px-6 md:pb-5">
            <div className="mx-auto max-w-3xl">
              <div className="mb-1 min-h-5 px-2 text-xs text-slate-600">
                {typing ? 'Someone is typing…' : ''}
              </div>
              <form
                onSubmit={submitMessage}
                className="flex items-end gap-2 rounded-2xl border border-white/10 bg-white/[0.045] p-2 shadow-lg shadow-black/10"
              >
                <button
                  type="button"
                  className="mb-0.5 rounded-xl p-2 text-slate-500 hover:bg-white/5 hover:text-white"
                >
                  <Plus className="size-4" />
                </button>
                <textarea
                  value={composer}
                  onChange={(event) =>
                    onComposerChange(event.target.value)
                  }
                  rows={1}
                  disabled={!channelId}
                  placeholder={
                    currentChannel
                      ? `Message #${currentChannel.name}…`
                      : 'Select a channel'
                  }
                  className="max-h-36 min-h-10 flex-1 resize-none bg-transparent px-1 py-2 text-sm outline-none placeholder:text-slate-600"
                  onKeyDown={(event) => {
                    if (
                      event.key === 'Enter' &&
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
                  disabled={!composer.trim() || !channelId}
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
                {currentWorkspace?.role ?? 'Member'} access
              </p>
            </div>
          </div>
          <div className="p-4">
            <div className="rounded-2xl border border-white/8 bg-white/[0.03] p-4">
              <Users className="size-4 text-[#68e0cf]" />
              <p className="mt-3 text-sm font-medium">Live workspace</p>
              <p className="mt-1 text-xs leading-5 text-slate-500">
                Presence, member directory and thread panels can attach here
                without changing the core conversation layout.
              </p>
            </div>
          </div>
        </aside>
      </div>
    </main>
  );
}

function PulseMeshClientInner() {
  const [token, setToken] = useState<string | null>(null);
  const [bootstrapping, setBootstrapping] = useState(true);

  useEffect(() => {
    let cancelled = false;
    request<{ accessToken: string }>('/auth/refresh', null, {
      method: 'POST',
      body: '{}'
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

  return (
    <WorkspaceApp
      token={token}
      onLoggedOut={() => setToken(null)}
    />
  );
}

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 15_000,
      refetchOnWindowFocus: false,
      retry: 1
    }
  }
});

export default function PulseMeshClient() {
  return (
    <QueryClientProvider client={queryClient}>
      <PulseMeshClientInner />
    </QueryClientProvider>
  );
}
