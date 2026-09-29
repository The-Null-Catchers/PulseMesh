import type { Conversation } from "./types";

export function initials(name: string) {
  return name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase())
    .join("");
}

export function conversationLabel(
  conversation: Conversation,
  currentUserId: string | null,
): string {
  if (conversation.name?.trim()) return conversation.name.trim();

  const visibleMembers =
    conversation.kind === "direct" && currentUserId
      ? conversation.members.filter((member) => member.id !== currentUserId)
      : conversation.members;

  const label = visibleMembers
    .map((member) => member.displayName.trim())
    .filter(Boolean)
    .join(", ");

  return label || "Conversation";
}
