"use client";

import { useQuery } from "@tanstack/react-query";
import { useState } from "react";
import { request } from "../lib/api";
import type { SearchResponse } from "../lib/types";

export function useGlobalSearch(token: string) {
  const [searchOpen, setSearchOpen] = useState(false);
  const [searchQuery, setSearchQuery] = useState("");

  const searchResults = useQuery({
    queryKey: ["global-search", searchQuery],
    enabled: searchOpen && searchQuery.trim().length >= 2,
    queryFn: () =>
      request<SearchResponse>(
        `/search?q=${encodeURIComponent(searchQuery.trim())}&limit=20`,
        token,
      ),
  });

  const closeSearch = () => {
    setSearchOpen(false);
    setSearchQuery("");
  };

  return {
    searchOpen,
    setSearchOpen,
    searchQuery,
    setSearchQuery,
    searchResults,
    closeSearch,
  };
}
