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


export function typingIndicatorText(
  names: string[],
  totalCount = names.length,
): string {
  if (totalCount <= 0) return "";

  const visibleNames = names.filter(Boolean);

  if (visibleNames.length === 0) {
    return totalCount === 1
      ? "Someone is typing…"
      : `${totalCount} people are typing…`;
  }

  if (totalCount === 1) {
    return `${visibleNames[0]} is typing…`;
  }

  if (totalCount === 2 && visibleNames.length >= 2) {
    return `${visibleNames[0]} and ${visibleNames[1]} are typing…`;
  }

  return `${visibleNames[0]} and ${totalCount - 1} others are typing…`;
}
