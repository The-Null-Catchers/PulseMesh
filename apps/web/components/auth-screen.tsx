"use client";

import { useMutation } from "@tanstack/react-query";
import { Loader2 } from "lucide-react";
import { FormEvent, useState } from "react";
import { request } from "../lib/api";

export function AuthScreen({
  onAuthenticated,
}: {
  onAuthenticated: (token: string) => void;
}) {
  const [mode, setMode] = useState<"login" | "register">("login");
  const [error, setError] = useState<string | null>(null);

  const auth = useMutation({
    mutationFn: async (form: FormData) => {
      const payload =
        mode === "login"
          ? {
              email: String(form.get("email") ?? ""),
              password: String(form.get("password") ?? ""),
              device: "PulseMesh Web",
              browser: navigator.userAgent.slice(0, 100),
            }
          : {
              email: String(form.get("email") ?? ""),
              password: String(form.get("password") ?? ""),
              username: String(form.get("username") ?? ""),
              displayName: String(form.get("displayName") ?? ""),
              device: "PulseMesh Web",
              browser: navigator.userAgent.slice(0, 100),
            };

      return request<{ accessToken: string }>(
        mode === "login" ? "/auth/login" : "/auth/register",
        null,
        { method: "POST", body: JSON.stringify(payload) },
      );
    },
    onSuccess: ({ accessToken }) => {
      setError(null);
      onAuthenticated(accessToken);
    },
    onError: (value) => {
      setError(
        value instanceof Error ? value.message : "Authentication failed",
      );
    },
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
              Channels, direct messaging, presence, media sessions and offline
              recovery on one production-oriented realtime core.
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
            {mode === "login" ? "Sign in" : "Create your account"}
          </h2>
          <p className="mt-2 text-sm text-slate-500">
            Your refresh session is kept in an HttpOnly cookie. Access tokens
            stay in memory.
          </p>

          <div className="mt-7 grid grid-cols-2 rounded-2xl border border-white/8 bg-white/[0.025] p-1">
            {(["login", "register"] as const).map((item) => (
              <button
                key={item}
                type="button"
                onClick={() => {
                  setMode(item);
                  setError(null);
                }}
                className={
                  "rounded-xl px-3 py-2 text-sm transition " +
                  (mode === item
                    ? "bg-white/[0.08] text-white"
                    : "text-slate-500 hover:text-slate-300")
                }
              >
                {item === "login" ? "Sign in" : "Register"}
              </button>
            ))}
          </div>

          <form className="mt-6 space-y-4" onSubmit={submit}>
            {mode === "register" && (
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
              <span className="mb-1.5 block text-xs text-slate-400">Email</span>
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
                  mode === "login" ? "current-password" : "new-password"
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
              {auth.isPending && <Loader2 className="size-4 animate-spin" />}
              {mode === "login" ? "Sign in" : "Create account"}
            </button>
          </form>
        </section>
      </div>
    </main>
  );
}
