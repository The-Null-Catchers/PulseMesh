"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Dispatch, SetStateAction, useState } from "react";
import { request } from "../lib/api";
import {
  markOptimisticMessageFailed,
  upsertOptimisticMessage,
} from "../lib/message-cache";
import type { Message, Page, UploadItem } from "../lib/types";

export function useMessageActions({
  token,
  activeMessageKey,
  channelId,
  conversationId,
  uploads,
  setUploads,
  activeThread,
  threadComposer,
  setThreadComposer,
}: {
  token: string;
  activeMessageKey: string | null;
  channelId: string | null;
  conversationId: string | null;
  uploads: UploadItem[];
  setUploads: Dispatch<SetStateAction<UploadItem[]>>;
  activeThread: Message | null;
  threadComposer: string;
  setThreadComposer: Dispatch<SetStateAction<string>>;
}) {
  const queryClient = useQueryClient();
  const [editingMessageId, setEditingMessageId] = useState<string | null>(null);
  const [editBody, setEditBody] = useState("");
  const [messageActionError, setMessageActionError] = useState<string | null>(
    null,
  );

  const invalidateActiveMessages = () => {
    if (!activeMessageKey) return;

    void queryClient.invalidateQueries({
      queryKey: ["messages", activeMessageKey],
    });
  };

  const sendMessage = useMutation({
    mutationFn: async ({
      body,
      clientMessageId,
      attachmentIds,
    }: {
      body: string;
      clientMessageId: string;
      attachmentIds: string[];
    }) => {
      if (!activeMessageKey) throw new Error("No conversation selected");

      const path = channelId
        ? `/channels/${channelId}/messages`
        : `/conversations/${conversationId}/messages`;

      return request(path, token, {
        method: "POST",
        body: JSON.stringify({
          body,
          clientMessageId,
          attachmentIds,
        }),
      });
    },
    onMutate: async ({ body, clientMessageId, attachmentIds }) => {
      if (!activeMessageKey) return;

      const key = ["messages", activeMessageKey] as const;
      await queryClient.cancelQueries({ queryKey: key });
      const previous = queryClient.getQueryData<Page<Message>>(key);

      const existing = previous?.items.find(
        (item) => item.clientMessageId === clientMessageId,
      );
      const uploadAttachments = uploads
        .filter((item) => item.fileId && attachmentIds.includes(item.fileId))
        .map((item) => ({
          id: item.fileId!,
          name: item.name,
          mimeType: item.file.type || "application/octet-stream",
          sizeBytes: item.file.size,
        }));

      const optimistic: Message = {
        id: clientMessageId,
        clientMessageId,
        channelId,
        conversationId,
        body,
        createdAt: existing?.createdAt ?? new Date().toISOString(),
        editedAt: null,
        attachments:
          uploadAttachments.length > 0
            ? uploadAttachments
            : (existing?.attachments ?? []),
        optimistic: true,
        sender: {
          id: "self",
          username: "you",
          displayName: "You",
          avatarUrl: null,
        },
      };

      queryClient.setQueryData<Page<Message>>(
        key,
        upsertOptimisticMessage(previous, optimistic),
      );

      return { key, clientMessageId };
    },
    onError: (error, variables, context) => {
      if (context?.key) {
        queryClient.setQueryData<Page<Message> | undefined>(
          context.key,
          (current) =>
            markOptimisticMessageFailed(current, variables.clientMessageId),
        );
      }
      setUploads((current) =>
        current.filter((item) => item.status !== "ready"),
      );
      setMessageActionError(
        error instanceof Error
          ? error.message
          : "Message failed to send. Retry from the message.",
      );
    },
    onSuccess: () => {
      setUploads((current) =>
        current.filter((item) => item.status !== "ready"),
      );
      setMessageActionError(null);
      invalidateActiveMessages();
    },
  });

  const reactionMutation = useMutation({
    mutationFn: async ({
      messageId,
      emoji,
      reacted,
    }: {
      messageId: string;
      emoji: string;
      reacted: boolean;
    }) =>
      request(
        `/messages/${messageId}/reactions/${encodeURIComponent(emoji)}`,
        token,
        { method: reacted ? "DELETE" : "PUT" },
      ),
    onSuccess: () => {
      setMessageActionError(null);
      invalidateActiveMessages();
    },
    onError: (error) =>
      setMessageActionError(
        error instanceof Error ? error.message : "Reaction failed",
      ),
  });

  const editMessage = useMutation({
    mutationFn: async ({
      messageId,
      body,
    }: {
      messageId: string;
      body: string;
    }) =>
      request(`/messages/${messageId}`, token, {
        method: "PATCH",
        body: JSON.stringify({ body }),
      }),
    onSuccess: () => {
      setEditingMessageId(null);
      setEditBody("");
      setMessageActionError(null);
      invalidateActiveMessages();
    },
    onError: (error) =>
      setMessageActionError(
        error instanceof Error ? error.message : "Edit failed",
      ),
  });

  const deleteMessage = useMutation({
    mutationFn: (messageId: string) =>
      request(`/messages/${messageId}?scope=everyone`, token, {
        method: "DELETE",
      }),
    onSuccess: () => {
      setMessageActionError(null);
      invalidateActiveMessages();
    },
    onError: (error) =>
      setMessageActionError(
        error instanceof Error ? error.message : "Delete failed",
      ),
  });

  const bookmarkMessage = useMutation({
    mutationFn: (messageId: string) =>
      request(`/messages/${messageId}/bookmark`, token, {
        method: "PUT",
        body: JSON.stringify({ note: null }),
      }),
    onSuccess: () => setMessageActionError(null),
    onError: (error) =>
      setMessageActionError(
        error instanceof Error ? error.message : "Bookmark failed",
      ),
  });

  const pinMessage = useMutation({
    mutationFn: (messageId: string) =>
      request(`/messages/${messageId}/pin`, token, {
        method: "POST",
        body: "{}",
      }),
    onSuccess: () => setMessageActionError(null),
    onError: (error) =>
      setMessageActionError(
        error instanceof Error ? error.message : "Pin failed",
      ),
  });

  const sendThreadReply = useMutation({
    mutationFn: async () => {
      if (!activeThread) throw new Error("No thread selected");

      const body = threadComposer.trim();
      if (!body) throw new Error("Reply cannot be empty");

      return request(`/messages/${activeThread.id}/thread`, token, {
        method: "POST",
        body: JSON.stringify({
          body,
          clientMessageId: crypto.randomUUID(),
        }),
      });
    },
    onSuccess: async () => {
      setThreadComposer("");
      setMessageActionError(null);
      await queryClient.invalidateQueries({
        queryKey: ["thread", activeThread?.id],
      });
      invalidateActiveMessages();
    },
    onError: (error) =>
      setMessageActionError(
        error instanceof Error ? error.message : "Reply failed",
      ),
  });

  const retryFailedMessage = (message: Message) => {
    if (!message.clientMessageId || sendMessage.isPending) return;

    sendMessage.mutate({
      body: message.body,
      clientMessageId: message.clientMessageId,
      attachmentIds: (message.attachments ?? []).map(
        (attachment) => attachment.id,
      ),
    });
  };

  return {
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
    invalidateActiveMessages,
  };
}
