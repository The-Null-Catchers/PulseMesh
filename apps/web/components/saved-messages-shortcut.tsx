"use client";

import { Bookmark } from "lucide-react";
import Link from "next/link";
import { usePathname } from "next/navigation";

export function SavedMessagesShortcut() {
  const pathname = usePathname();
  if (pathname === "/saved") return null;

  return (
    <Link
      href="/saved"
      className="fixed bottom-5 right-5 z-40 flex items-center gap-2 rounded-2xl border border-white/10 bg-[#0a171d]/95 px-3.5 py-2.5 text-sm font-medium text-slate-300 shadow-xl shadow-black/30 backdrop-blur transition hover:border-[#68e0cf]/30 hover:text-white"
      aria-label="Open saved messages"
    >
      <Bookmark className="size-4 text-[#68e0cf]" />
      <span className="hidden sm:inline">Saved</span>
    </Link>
  );
}
