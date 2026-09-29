"use client";

import { useEffect, useRef } from "react";

export function RemoteMedia({
  stream,
  video,
}: {
  stream: MediaStream;
  video: boolean;
}) {
  const ref = useRef<HTMLMediaElement | null>(null);

  useEffect(() => {
    if (ref.current) ref.current.srcObject = stream;
  }, [stream]);

  return video ? (
    <video
      ref={(element) => {
        ref.current = element;
      }}
      autoPlay
      playsInline
      className="h-full w-full object-cover"
    />
  ) : (
    <audio
      ref={(element) => {
        ref.current = element;
      }}
      autoPlay
    />
  );
}
