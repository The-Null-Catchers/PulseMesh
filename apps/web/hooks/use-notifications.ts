"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { request } from "../lib/api";
import type { NotificationItem } from "../lib/types";

export function useNotifications(token: string) {
  const queryClient = useQueryClient();
  const [notificationsOpen, setNotificationsOpen] = useState(false);

  const notifications = useQuery({
    queryKey: ["notifications"],
    queryFn: () =>
      request<{ items: NotificationItem[] }>("/notifications", token),
  });

  const markNotificationRead = useMutation({
    mutationFn: (notificationId: string) =>
      request(`/notifications/${notificationId}/read`, token, {
        method: "POST",
        body: "{}",
      }),
    onSuccess: () =>
      queryClient.invalidateQueries({ queryKey: ["notifications"] }),
  });

  const markAllNotificationsRead = useMutation({
    mutationFn: () =>
      request("/notifications/read-all", token, {
        method: "POST",
        body: "{}",
      }),
    onSuccess: () =>
      queryClient.invalidateQueries({ queryKey: ["notifications"] }),
  });

  const unreadNotificationCount = (notifications.data?.items ?? []).filter(
    (item) => !item.read_at,
  ).length;

  return {
    notificationsOpen,
    setNotificationsOpen,
    notifications,
    markNotificationRead,
    markAllNotificationsRead,
    unreadNotificationCount,
  };
}
