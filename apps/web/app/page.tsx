import {
  Bell,
  ChevronDown,
  Hash,
  Headphones,
  Mic,
  MoreHorizontal,
  Plus,
  Search,
  Send,
  Smile,
  Sparkles,
  Users,
  Volume2
} from 'lucide-react';

const channels = ['general', 'backend', 'mobile', 'design', 'random'];

const messages = [
  {
    name: 'Mohammed',
    time: '01:18',
    body: 'API deployment finished. Health checks are green and Redis fanout is passing across both replicas.',
    badge: 'M',
    online: true
  },
  {
    name: 'Lama',
    time: '01:21',
    body: 'Great. I will test reconnect, optimistic messages, and missed-message sync from Android now.',
    badge: 'L',
    online: true
  },
  {
    name: 'Ibrahim',
    time: '01:26',
    body: 'TURN is reachable too. I added the production firewall notes to the WebRTC deployment checklist.',
    badge: 'I',
    online: false
  }
];

const members = [
  { name: 'Mohammed', role: 'Product engineering', online: true },
  { name: 'Lama', role: 'Flutter', online: true },
  { name: 'Abdullah', role: 'Growth & mobile', online: true },
  { name: 'Ibrahim', role: 'Backend & Linux', online: false },
  { name: 'Shorouq', role: 'Design', online: false }
];

function Avatar({ label, online = true }: { label: string; online?: boolean }) {
  return (
    <div className="relative grid size-10 shrink-0 place-items-center rounded-2xl border border-white/10 bg-white/6 text-sm font-semibold">
      {label}
      <span
        className={
          'absolute -bottom-0.5 -right-0.5 size-3 rounded-full border-2 border-[#0a1419] ' +
          (online ? 'bg-emerald-400' : 'bg-slate-500')
        }
      />
    </div>
  );
}

export default function Home() {
  return (
    <main className="min-h-screen p-3 md:p-4">
      <div className="mx-auto grid h-[calc(100vh-24px)] max-w-[1700px] grid-cols-[72px_minmax(0,1fr)] overflow-hidden rounded-[28px] border border-white/10 bg-[#09151a]/80 shadow-2xl shadow-black/30 sm:grid-cols-[72px_260px_minmax(0,1fr)] md:h-[calc(100vh-32px)] xl:grid-cols-[72px_270px_minmax(0,1fr)_280px]">
        <aside className="flex flex-col items-center gap-3 border-r border-white/8 bg-[#071116]/80 py-4">
          <div className="mb-2 grid size-11 place-items-center rounded-2xl bg-[linear-gradient(135deg,#68e0cf,#73a7ff)] font-black text-[#061013] shadow-lg shadow-cyan-950/30">
            P
          </div>
          {['N', 'D', 'C'].map((item, index) => (
            <button
              key={item}
              className={
                'grid size-11 place-items-center rounded-2xl border text-sm font-semibold transition ' +
                (index === 0
                  ? 'border-[#68e0cf]/35 bg-[#68e0cf]/12 text-[#9af5e8]'
                  : 'border-white/8 bg-white/[0.035] text-slate-400 hover:bg-white/[0.07]')
              }
              aria-label={'Workspace ' + item}
            >
              {item}
            </button>
          ))}
          <button
            className="grid size-11 place-items-center rounded-2xl border border-dashed border-white/15 text-slate-500 hover:text-slate-200"
            aria-label="Add workspace"
          >
            <Plus className="size-4" />
          </button>
          <div className="mt-auto">
            <Avatar label="ME" />
          </div>
        </aside>

        <aside className="hidden border-r border-white/8 bg-[#0a151a]/85 sm:flex sm:flex-col">
          <div className="flex h-16 items-center justify-between border-b border-white/8 px-4">
            <div>
              <p className="text-xs uppercase tracking-[0.18em] text-[#68e0cf]/70">Workspace</p>
              <button className="mt-0.5 flex items-center gap-1 font-semibold">
                The Null Catchers <ChevronDown className="size-4 text-slate-500" />
              </button>
            </div>
            <button className="rounded-xl p-2 text-slate-500 hover:bg-white/5 hover:text-white" aria-label="Workspace menu">
              <MoreHorizontal className="size-4" />
            </button>
          </div>

          <div className="p-3">
            <button className="flex w-full items-center gap-2 rounded-xl border border-white/8 bg-white/[0.035] px-3 py-2 text-left text-sm text-slate-400">
              <Search className="size-4" />
              Jump to anything
              <span className="ml-auto rounded-md border border-white/8 px-1.5 py-0.5 text-[10px]">⌘K</span>
            </button>
          </div>

          <nav className="flex-1 overflow-y-auto px-3 pb-3">
            <div className="mb-2 flex items-center justify-between px-2 pt-2 text-[11px] font-semibold uppercase tracking-[0.16em] text-slate-500">
              Channels
              <Plus className="size-3.5" />
            </div>
            <div className="space-y-1">
              {channels.map((channel) => (
                <button
                  key={channel}
                  className={
                    'flex w-full items-center gap-2 rounded-xl px-2.5 py-2 text-sm ' +
                    (channel === 'backend'
                      ? 'bg-[linear-gradient(90deg,rgba(104,224,207,.11),rgba(115,167,255,.05))] text-white'
                      : 'text-slate-400 hover:bg-white/[0.04] hover:text-slate-200')
                  }
                >
                  <Hash className="size-4 opacity-60" />
                  {channel}
                  {channel === 'backend' && <span className="ml-auto size-1.5 rounded-full bg-[#68e0cf]" />}
                </button>
              ))}
            </div>

            <div className="mb-2 mt-6 flex items-center justify-between px-2 text-[11px] font-semibold uppercase tracking-[0.16em] text-slate-500">
              Voice
              <Plus className="size-3.5" />
            </div>
            <button className="flex w-full items-center gap-2 rounded-xl px-2.5 py-2 text-sm text-slate-400 hover:bg-white/[0.04]">
              <Volume2 className="size-4" />
              Daily sync
              <span className="ml-auto text-xs text-emerald-400">3</span>
            </button>
          </nav>

          <div className="m-3 rounded-2xl border border-white/8 bg-white/[0.035] p-3">
            <div className="flex items-center gap-2">
              <Avatar label="ME" />
              <div className="min-w-0">
                <p className="truncate text-sm font-medium">Mohammed</p>
                <p className="text-xs text-emerald-400">Available</p>
              </div>
              <div className="ml-auto flex gap-1">
                <button className="rounded-lg p-1.5 text-slate-500 hover:bg-white/5" aria-label="Mute">
                  <Mic className="size-4" />
                </button>
                <button className="rounded-lg p-1.5 text-slate-500 hover:bg-white/5" aria-label="Deafen">
                  <Headphones className="size-4" />
                </button>
              </div>
            </div>
          </div>
        </aside>

        <section className="flex min-w-0 flex-col bg-[#0b171c]/70">
          <header className="flex h-16 items-center gap-3 border-b border-white/8 px-4 md:px-5">
            <div className="grid size-9 place-items-center rounded-xl bg-white/[0.04]">
              <Hash className="size-4 text-[#82e9dc]" />
            </div>
            <div className="min-w-0">
              <h1 className="font-semibold">backend</h1>
              <p className="truncate text-xs text-slate-500">API, infrastructure and realtime systems</p>
            </div>
            <div className="ml-auto flex items-center gap-1">
              <button className="rounded-xl p-2 text-slate-500 hover:bg-white/5 hover:text-white" aria-label="Search">
                <Search className="size-4" />
              </button>
              <button className="rounded-xl p-2 text-slate-500 hover:bg-white/5 hover:text-white" aria-label="Notifications">
                <Bell className="size-4" />
              </button>
              <button className="rounded-xl p-2 text-slate-500 hover:bg-white/5 hover:text-white xl:hidden" aria-label="Members">
                <Users className="size-4" />
              </button>
            </div>
          </header>

          <div className="relative flex-1 overflow-y-auto px-4 py-6 md:px-7">
            <div className="mx-auto max-w-3xl">
              <div className="mb-8 rounded-3xl border border-[#68e0cf]/15 bg-[linear-gradient(135deg,rgba(104,224,207,.08),rgba(115,167,255,.04))] p-5">
                <div className="mb-3 flex items-center gap-2 text-[#8beadd]">
                  <Sparkles className="size-4" />
                  <span className="text-xs font-semibold uppercase tracking-[0.16em]">Channel brief</span>
                </div>
                <h2 className="text-lg font-semibold">Ship reliable realtime systems.</h2>
                <p className="mt-1 max-w-xl text-sm leading-6 text-slate-400">
                  Use this channel for backend architecture, deployments, observability, WebSockets and database changes.
                </p>
              </div>

              <div className="space-y-7">
                {messages.map((message, index) => (
                  <article key={message.name + message.time} className="group flex gap-3">
                    <Avatar label={message.badge} online={message.online} />
                    <div className="min-w-0 flex-1">
                      <div className="flex items-baseline gap-2">
                        <h3 className="text-sm font-semibold">{message.name}</h3>
                        <span className="text-[11px] text-slate-600">{message.time}</span>
                      </div>
                      <p className="mt-1 max-w-2xl text-[15px] leading-6 text-slate-300">{message.body}</p>
                      {index === 0 && (
                        <div className="mt-3 flex gap-2">
                          <button className="rounded-xl border border-white/8 bg-white/[0.035] px-2.5 py-1 text-xs text-slate-300">👍 4</button>
                          <button className="rounded-xl border border-white/8 bg-white/[0.035] px-2.5 py-1 text-xs text-slate-300">🔥 2</button>
                        </div>
                      )}
                    </div>
                  </article>
                ))}
              </div>
            </div>
          </div>

          <div className="px-4 pb-4 md:px-6 md:pb-5">
            <div className="mx-auto flex max-w-3xl items-end gap-2 rounded-2xl border border-white/10 bg-white/[0.045] p-2 shadow-lg shadow-black/10">
              <button className="mb-0.5 rounded-xl p-2 text-slate-500 hover:bg-white/5 hover:text-white" aria-label="Attach file">
                <Plus className="size-4" />
              </button>
              <div className="min-h-10 flex-1 px-1 py-2 text-sm text-slate-500">Message #backend...</div>
              <button className="mb-0.5 rounded-xl p-2 text-slate-500 hover:bg-white/5 hover:text-white" aria-label="Emoji">
                <Smile className="size-4" />
              </button>
              <button className="mb-0.5 grid size-9 place-items-center rounded-xl bg-[#68e0cf] text-[#061013]" aria-label="Send">
                <Send className="size-4" />
              </button>
            </div>
          </div>
        </section>

        <aside className="hidden border-l border-white/8 bg-[#091419]/85 xl:flex xl:flex-col">
          <div className="flex h-16 items-center border-b border-white/8 px-4">
            <div>
              <p className="font-semibold">Members</p>
              <p className="text-xs text-slate-500">3 online · 5 total</p>
            </div>
          </div>
          <div className="space-y-1 p-3">
            {members.map((member) => (
              <button
                key={member.name}
                className="flex w-full items-center gap-3 rounded-2xl px-2 py-2.5 text-left hover:bg-white/[0.04]"
              >
                <Avatar label={member.name.slice(0, 1)} online={member.online} />
                <div className="min-w-0">
                  <p className="truncate text-sm font-medium">{member.name}</p>
                  <p className="truncate text-xs text-slate-500">{member.role}</p>
                </div>
              </button>
            ))}
          </div>
        </aside>
      </div>
    </main>
  );
}
