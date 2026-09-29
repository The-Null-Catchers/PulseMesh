"use client";

import { useRef, useState } from "react";
import { request } from "../lib/api";
import type { Attachment, UploadItem } from "../lib/types";

export function useFileUploads({
  token,
  isEncryptedConversation,
}: {
  token: string;
  isEncryptedConversation: boolean;
}) {
  const [uploads, setUploads] = useState<UploadItem[]>([]);
  const [uploadError, setUploadError] = useState<string | null>(null);
  const uploadXhrsRef = useRef<Map<string, XMLHttpRequest>>(new Map());

  async function waitForFileReady(
    fileId: string,
    localId: string,
  ): Promise<void> {
    for (let attempt = 0; attempt < 40; attempt += 1) {
      const result = await request<{
        status: string;
        processingError?: string | null;
      }>(`/files/${fileId}`, token);

      if (result.status === "ready") {
        setUploads((current) =>
          current.map((item) =>
            item.localId === localId
              ? { ...item, status: "ready", progress: 100, error: null }
              : item,
          ),
        );
        return;
      }

      if (result.status === "rejected") {
        throw new Error(
          result.processingError || "File processing was rejected",
        );
      }

      await new Promise((resolve) => setTimeout(resolve, 1000));
    }

    throw new Error("File processing timed out");
  }

  async function uploadFile(file: File, existingLocalId?: string) {
    if (isEncryptedConversation) {
      setUploadError(
        "Attachments are disabled until this web client supports libsignal encryption.",
      );
      return;
    }

    setUploadError(null);
    const localId = existingLocalId ?? crypto.randomUUID();

    setUploads((current) => {
      const existing = current.find((item) => item.localId === localId);

      if (existing) {
        return current.map((item) =>
          item.localId === localId
            ? {
                ...item,
                fileId: null,
                status: "uploading",
                progress: 0,
                error: null,
              }
            : item,
        );
      }

      return [
        ...current,
        {
          localId,
          fileId: null,
          file,
          name: file.name,
          status: "uploading",
          progress: 0,
          error: null,
        },
      ];
    });

    try {
      const presign = await request<{
        fileId: string;
        uploadUrl: string;
        headers: Record<string, string>;
      }>("/files/presign", token, {
        method: "POST",
        body: JSON.stringify({
          name: file.name,
          mimeType: file.type || "application/octet-stream",
          sizeBytes: file.size,
        }),
      });

      setUploads((current) =>
        current.map((item) =>
          item.localId === localId ? { ...item, fileId: presign.fileId } : item,
        ),
      );

      await new Promise<void>((resolve, reject) => {
        const xhr = new XMLHttpRequest();
        uploadXhrsRef.current.set(localId, xhr);
        xhr.open("PUT", presign.uploadUrl);

        Object.entries(presign.headers).forEach(([key, value]) => {
          xhr.setRequestHeader(key, value);
        });

        xhr.upload.onprogress = (event) => {
          if (!event.lengthComputable) return;

          const progress = Math.round((event.loaded / event.total) * 100);
          setUploads((current) =>
            current.map((item) =>
              item.localId === localId ? { ...item, progress } : item,
            ),
          );
        };

        xhr.onload = () => {
          uploadXhrsRef.current.delete(localId);

          if (xhr.status >= 200 && xhr.status < 300) {
            resolve();
          } else {
            reject(new Error("Object storage upload failed"));
          }
        };

        xhr.onerror = () => {
          uploadXhrsRef.current.delete(localId);
          reject(new Error("Object storage upload failed"));
        };

        xhr.onabort = () => {
          uploadXhrsRef.current.delete(localId);
          reject(new Error("Upload cancelled"));
        };

        xhr.send(file);
      });

      setUploads((current) =>
        current.map((item) =>
          item.localId === localId
            ? { ...item, status: "processing", progress: 100 }
            : item,
        ),
      );

      await request(`/files/${presign.fileId}/complete`, token, {
        method: "POST",
        body: "{}",
      });

      await waitForFileReady(presign.fileId, localId);
    } catch (error) {
      setUploads((current) =>
        current.map((item) =>
          item.localId === localId
            ? {
                ...item,
                status:
                  error instanceof Error && error.message === "Upload cancelled"
                    ? "cancelled"
                    : "failed",
                error: error instanceof Error ? error.message : "Upload failed",
              }
            : item,
        ),
      );
    }
  }

  async function cancelUpload(item: UploadItem) {
    uploadXhrsRef.current.get(item.localId)?.abort();

    if (item.fileId) {
      try {
        await request(`/files/${item.fileId}`, token, {
          method: "DELETE",
        });
      } catch {
        // A file that is already processing/attached may no longer be cancellable.
      }
    }

    setUploads((current) =>
      current.filter((candidate) => candidate.localId !== item.localId),
    );
  }

  async function downloadAttachment(attachment: Attachment) {
    try {
      setUploadError(null);
      const result = await request<{ url: string }>(
        `/files/${attachment.id}/download`,
        token,
        { method: "POST", body: "{}" },
      );

      window.open(result.url, "_blank", "noopener,noreferrer");
    } catch (error) {
      setUploadError(
        error instanceof Error ? error.message : "Download failed",
      );
    }
  }

  return {
    uploads,
    setUploads,
    uploadError,
    setUploadError,
    uploadFile,
    cancelUpload,
    downloadAttachment,
  };
}
