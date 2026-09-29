import {
  realtimeControlMessageSchema,
  realtimeEventSchema,
  type RealtimeEvent
} from '@pulsemesh/realtime';
import type { ApiErrorEnvelope } from '@pulsemesh/types';

export class PulseMeshApiError extends Error {
  constructor(
    readonly code: string,
    message: string,
    readonly requestId: string
  ) {
    super(message);
  }
}

export class PulseMeshClient {
  constructor(
    private readonly baseUrl: string,
    private readonly accessToken?: () => string | null
  ) {}

  async request<T>(path: string, init: RequestInit = {}): Promise<T> {
    const token = this.accessToken?.();
    const response = await fetch(this.baseUrl + path, {
      ...init,
      headers: {
        'content-type': 'application/json',
        ...(token ? { authorization: 'Bearer ' + token } : {}),
        ...init.headers
      }
    });
    if (!response.ok) {
      const body = (await response.json()) as ApiErrorEnvelope;
      throw new PulseMeshApiError(
        body.error.code,
        body.error.message,
        body.error.requestId
      );
    }
    return (await response.json()) as T;
  }
}

export type RealtimeConnectionState =
  | 'idle'
  | 'connecting'
  | 'connected'
  | 'ready'
  | 'reconnecting'
  | 'closed';

export interface PulseMeshRealtimeOptions {
  socketUrl: string;
  getTicket: () => Promise<string>;
  onEvent: (event: RealtimeEvent) => void;
  onStateChange?: (state: RealtimeConnectionState) => void;
  onSequence?: (sequence: number) => void;
  initialSequence?: number;
  maxBackoffMs?: number;
}

export class PulseMeshRealtimeClient {
  private socket: WebSocket | null = null;
  private stopped = true;
  private reconnectAttempts = 0;
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private readonly rooms = new Set<string>();
  private readonly seenIds = new Set<string>();
  private readonly seenOrder: string[] = [];
  private lastSequence: number;
  private activeView: string | null = null;

  constructor(private readonly options: PulseMeshRealtimeOptions) {
    this.lastSequence = options.initialSequence ?? 0;
  }

  async connect(): Promise<void> {
    this.stopped = false;
    try {
      await this.open();
    } catch {
      this.scheduleReconnect();
    }
  }

  disconnect(): void {
    this.stopped = true;
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    this.socket?.close(1000, 'Client disconnect');
    this.socket = null;
    this.emitState('closed');
  }

  subscribe(room: string): void {
    this.rooms.add(room);
    this.send({ type: 'room.subscribe', room });
  }

  unsubscribe(room: string): void {
    this.rooms.delete(room);
    if (this.activeView === room) this.activeView = null;
    this.send({ type: 'room.unsubscribe', room });
  }

  setActiveView(room: string | null): void {
    this.activeView = room;
    this.send({ type: 'view.active', room });
  }

  heartbeat(): void {
    this.send({ type: 'presence.heartbeat' });
  }

  setTyping(room: string, typing: boolean): void {
    if (!this.rooms.has(room)) return;
    this.send({
      type: typing ? 'typing.started' : 'typing.stopped',
      room
    });
  }

  get sequence(): number {
    return this.lastSequence;
  }

  private async open(): Promise<void> {
    if (this.stopped) return;
    if (
      this.socket &&
      (this.socket.readyState === WebSocket.CONNECTING ||
        this.socket.readyState === WebSocket.OPEN)
    ) {
      return;
    }

    this.emitState(
      this.reconnectAttempts > 0 ? 'reconnecting' : 'connecting'
    );
    const ticket = await this.options.getTicket();
    if (this.stopped) return;

    const url = new URL(this.options.socketUrl);
    url.searchParams.set('ticket', ticket);
    const socket = new WebSocket(url);
    this.socket = socket;

    socket.onopen = () => {
      if (this.socket !== socket) return;
      this.reconnectAttempts = 0;
      this.emitState('connected');
    };

    socket.onmessage = (message) => {
      if (this.socket !== socket) return;
      this.handleMessage(message.data);
    };

    socket.onerror = () => {
      if (this.socket === socket) socket.close();
    };

    socket.onclose = () => {
      if (this.socket !== socket) return;
      this.socket = null;
      if (this.stopped) return;
      this.scheduleReconnect();
    };
  }

  private handleMessage(raw: unknown): void {
    let value: unknown;
    try {
      value = JSON.parse(
        typeof raw === 'string' ? raw : String(raw)
      );
    } catch {
      return;
    }

    const control = realtimeControlMessageSchema.safeParse(value);
    if (control.success) {
      if (control.data.type === 'session.ready') {
        this.send({
          type: 'session.resume',
          lastSequence: this.lastSequence,
          rooms: [...this.rooms]
        });
      } else {
        if (this.activeView) {
          this.send({ type: 'view.active', room: this.activeView });
        }
        this.emitState('ready');
      }
      return;
    }

    const event = realtimeEventSchema.safeParse(value);
    if (!event.success || this.seenIds.has(event.data.id)) return;

    this.rememberEvent(event.data.id);
    if (
      typeof event.data.sequence === 'number' &&
      event.data.sequence > this.lastSequence
    ) {
      this.lastSequence = event.data.sequence;
      this.options.onSequence?.(this.lastSequence);
    }
    this.options.onEvent(event.data);
  }

  private rememberEvent(id: string): void {
    this.seenIds.add(id);
    this.seenOrder.push(id);
    if (this.seenOrder.length <= 2_048) return;

    const oldest = this.seenOrder.shift();
    if (oldest) this.seenIds.delete(oldest);
  }

  private send(value: unknown): void {
    if (
      !this.socket ||
      this.socket.readyState !== WebSocket.OPEN
    ) {
      return;
    }
    this.socket.send(JSON.stringify(value));
  }

  private scheduleReconnect(): void {
    if (this.stopped || this.reconnectTimer) return;

    this.emitState('reconnecting');
    const maxBackoff = this.options.maxBackoffMs ?? 30_000;
    const exponential = Math.min(
      1_000 * 2 ** Math.min(this.reconnectAttempts, 5),
      maxBackoff
    );
    const delay = exponential + Math.floor(Math.random() * 250);
    this.reconnectAttempts += 1;

    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null;
      void this.open().catch(() => this.scheduleReconnect());
    }, delay);
  }

  private emitState(state: RealtimeConnectionState): void {
    this.options.onStateChange?.(state);
  }
}
