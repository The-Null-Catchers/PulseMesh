"use client";

import {
  QueryClient,
  QueryClientProvider,
  useMutation,
  useQuery,
  useQueryClient,
} from "@tanstack/react-query";
import { ArrowLeft, Bookmark, Loader2, Pencil, Trash2 } from "lucide-react";
import Link from "next/link";
import { useCallback, useEffect, useRef, useState } from "react";
import { request, setAccessTokenRefresher } from "../../lib/api";

type SavedMessage = {
  messageId: string;
  note: string | null;
  createdAt: string;
  updatedAt: string;
  message: {
    id: string;
    channelId: string | null;
    conversationId: string | null;
    body: string;
    createdAt: string;
    editedAt: string | null;
    sender: {
      id: string;
      username: string;
      displayName: string;
      avatarUrl: string | null;
    };
  };
};

type BookmarkPage = {
  items: SavedMessage[];
  nextCursor: string | null;
};

function SavedMessagesView({ token }: { token: string }) {
  const queryClient = useQueryClient();
  const [editingId, setEditingId] = useState<string | null>(null);
  const [noteDraft, setNoteDraft] = useState("");
  const [error, setError] = useState<string | null>(null);

  const bookmarks = useQuery({
    queryKey: ["bookmarks"],
    queryFn: () => request<BookmarkPage>("/bookmarks?limit=100", token),
  });

  const updateNote = useMutation({
    mutationFn: ({ messageId, note }: { messageId: string; note: string }) =>
      request(`/messages/${messageId}/bookmark`, token, {
        method: "PUT",
        body: JSON.stringify({ note: note.trim() || null }),
      }),
    onSuccess: async () => {
      setEditingId(null);
      setNoteDraft("");
      setError(null);
      await queryClient.invalidateQueries({ queryKey: ["bookmarks"] });
    },
    onError: (mutationError) => {
      setError(
        mutationError instanceof Error
          ? mutationError.message
          : "Could not update the saved note.",
      );
    },
  });

  const removeBookmark = useMutation({
    mutationFn: (messageId: string) =>
      request(`/messages/${messageId}/bookmark`, token, {
        method: "DELETE",
      }),
    onSuccess: async () => {
      setError(null);
      await queryClient.invalidateQueries({ queryKey: ["bookmarks"] });
    },
    onError: (mutationError) => {
      setError(
        mutationError instanceof Error
          ? mutationError.message
          : "Could not remove the saved message.",
      );
    },
  });

  return (
    <main className="min-h-screen bg-[#071116] p-4 text-slate-100 md:p-8">
      <div className="mx-auto max-w-4xl">
        <div className="mb-6 flex flex-wrap items-center gap-3">
          <Link
            href="/"
            className="grid size-10 place-items-center rounded-2xl border border-white/10 bg-white/[0.035] text-slate-400 transition hover:bg-white/[0.07] hover:text-white"
            aria-label="Back to PulseMesh"
          >
            <ArrowLeft className="size-4" />
          </Link>
          <div>
            <p className="text-xs font-semibold uppercase tracking-[0.18em] text-[#68e0cf]">
              PulseMesh
            </p>
            <h1 className="mt-1 text-2xl font-semibold">Saved Messages</h1>
            <p className="mt-1 text-sm text-slate-500">
              Private bookmarks and notes only you can see.
            </p>
          </div>
        </div>

        {error && (
          <div className="mb-4 rounded-2xl border border-rose-400/20 bg-rose-400/10 px-4 py-3 text-sm text-rose-200">
            {error}
          </div>
        )}

        {bookmarks.isLoading ? (
          <div className="grid h-56 place-items-center rounded-[28px] border border-white/10 bg-[#0b171c]/70">
            <Loader2 className="size-6 animate-spin text-[#68e0cf]" />
          </div>
        ) : bookmarks.error ? (
          <div className="rounded-[28px] border border-rose-400/20 bg-rose-400/10 p-6 text-sm text-rose-200">
            {bookmarks.error instanceof Error
              ? bookmarks.error.message
              : "Could not load saved messages."}
          </div>
        ) : bookmarks.data?.items.length ? (
          <div className="space-y-3">
            {bookmarks.data.items.map((item) => (
              <article
                key={item.messageId}
                className="rounded-[24px] border border-white/10 bg-[#0b171c]/80 p-4 shadow-xl shadow-black/10"
              >
                <div className="flex items-start gap-3">
                  <div className="mt-0.5 grid size-10 shrink-0 place-items-center rounded-2xl bg-[#68e0cf]/10 text-[#9af5e8]">
                    <Bookmark className="size-4" />
                  </div>
                  <div className="min-w-0 flex-1">
                    <div className="flex flex-wrap items-baseline gap-x-2 gap-y-1">
                      <h2 className="text-sm font-semibold">
                        {item.message.sender.displayName}
                      </h2>
                      <span className="text-xs text-slate-600">
                        @{item.message.sender.username}
                      </span>
                      <span className="text-[11px] text-slate-600">
                        {new Date(item.message.createdAt).toLocaleString()}
                      </span>
                    </div>
                    <p className="mt-2 whitespace-pre-wrap break-words text-[15px] leading-6 text-slate-300">
                      {item.message.body || "Message without text"}
                    </p>

                    {editingId === item.messageId ? (
                      <div className="mt-4">
                        <textarea
                          value={noteDraft}
                          onChange={(event) => setNoteDraft(event.target.value)}
                          maxLength={2000}
                          rows={3}
                          className="w-full resize-none rounded-2xl border border-white/10 bg-white/[0.035] px-3 py-2 text-sm outline-none focus:border-[#68e0cf]/40"
                          placeholder="Add a private note…"
                          autoFocus
                        />
                        <div className="mt-2 flex items-center gap-2">
                          <button
                            type="button"
                            onClick={() =>
                              updateNote.mutate({
                                messageId: item.messageId,
                                note: noteDraft,
                              })
                            }
                            disabled={updateNote.isPending}
                            className="rounded-xl bg-[#68e0cf] px-3 py-1.5 text-xs font-semibold text-[#061013] disabled:opacity-50"
                          >
                            Save note
                          </button>
                          <button
                            type="button"
                            onClick={() => {
                              setEditingId(null);
                              setNoteDraft("");
                            }}
                            className="rounded-xl border border-white/10 px-3 py-1.5 text-xs text-slate-400"
                          >
                            Cancel
                          </button>
                        </div>
                      </div>
                    ) : item.note ? (
                      <div className="mt-4 rounded-2xl border border-[#68e0cf]/10 bg-[#68e0cf]/[0.04] px-3 py-2 text-sm text-slate-300">
                        <span className="mb-1 block text-[10px] font-semibold uppercase tracking-[0.14em] text-[#68e0cf]/70">
                          Private note
                        </span>
                        {item.note}
                      </div>
                    ) : null}
                  </div>

                  <div className="flex shrink-0 items-center gap-1">
                    <button
                      type="button"
                      onClick={() => {
                        setEditingId(item.messageId);
                        setNoteDraft(item.note ?? "");
                      }}
                      className="rounded-xl p-2 text-slate-500 hover:bg-white/5 hover:text-white"
                      aria-label="Edit private note"
                    >
                      <Pencil className="size-4" />
                    </button>
                    <button
                      type="button"
                      onClick={() => removeBookmark.mutate(item.messageId)}
                      disabled={removeBookmark.isPending}
                      className="rounded-xl p-2 text-slate-500 hover:bg-rose-400/10 hover:text-rose-300 disabled:opacity-50"
                      aria-label="Remove saved message"
                    >
                      <Trash2 className="size-4" />
                    </button>
                  </div>
                </div>
              </article>
            ))}
          </div>
        ) : (
          <div className="rounded-[28px] border border-dashed border-white/10 bg-[#0b171c]/50 p-10 text-center">
            <Bookmark className="mx-auto size-7 text-[#68e0cf]" />
            <h2 className="mt-4 text-lg font-semibold">Nothing saved yet</h2>
            <p className="mx-auto mt-2 max-w-md text-sm leading-6 text-slate-500">
              Use the bookmark action on any message, then it will appear here.
            </p>
          </div>
        )}
      </div>
    </main>
  );
}

function SavedMessagesClientInner() {
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
    void refreshSession().finally(() => {
      if (!cancelled) setBootstrapping(false);
    });

    return () => {
      cancelled = true;
    };
  }, [refreshSession]);

  if (bootstrapping) {
    return (
      <main className="grid min-h-screen place-items-center bg-[#071116] text-slate-400">
        <div className="flex items-center gap-3 text-sm">
          <Loader2 className="size-5 animate-spin text-[#68e0cf]" />
          Restoring session…
        </div>
      </main>
    );
  }

  if (!token) {
    return (
      <main className="grid min-h-screen place-items-center bg-[#071116] p-6 text-slate-100">
        <div className="max-w-md rounded-[28px] border border-white/10 bg-[#0b171c] p-8 text-center">
          <Bookmark className="mx-auto size-7 text-[#68e0cf]" />
          <h1 className="mt-4 text-xl font-semibold">Sign in to view saved messages</h1>
          <p className="mt-2 text-sm leading-6 text-slate-500">
            Your saved messages are private and require an active PulseMesh session.
          </p>
          <Link
            href="/"
            className="mt-5 inline-flex rounded-2xl bg-[#68e0cf] px-4 py-2.5 text-sm font-semibold text-[#061013]"
          >
            Go to PulseMesh
          </Link>
        </div>
      </main>
    );
  }

  return <SavedMessagesView token={token} />;
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

export default function SavedMessagesClient() {
  return (
    <QueryClientProvider client={queryClient}>
      <SavedMessagesClientInner />
    </QueryClientProvider>
  );
}
