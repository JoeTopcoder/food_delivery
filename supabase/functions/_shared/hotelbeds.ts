import { crypto } from "https://deno.land/std@0.177.0/crypto/mod.ts";
import { encode as hexEncode } from "https://deno.land/std@0.177.0/encoding/hex.ts";

export const HOTELBEDS_BASE_TEST = "https://api.test.hotelbeds.com";
export const HOTELBEDS_BASE_LIVE = "https://api.hotelbeds.com";

export function getHotelbedsBase(mode: string): string {
  return mode === "live" ? HOTELBEDS_BASE_LIVE : HOTELBEDS_BASE_TEST;
}

/** SHA256(apiKey + secret + unixTimestamp) */
export async function buildSignature(apiKey: string, secret: string): Promise<string> {
  const ts = Math.floor(Date.now() / 1000).toString();
  const raw = apiKey + secret + ts;
  const encoded = new TextEncoder().encode(raw);
  const hashBuf = await crypto.subtle.digest("SHA-256", encoded);
  const hex = hexEncode(new Uint8Array(hashBuf));
  return new TextDecoder().decode(hex);
}

export async function hotelbedsHeaders(apiKey: string, secret: string): Promise<Record<string, string>> {
  const sig = await buildSignature(apiKey, secret);
  return {
    "Api-key": apiKey,
    "X-Signature": sig,
    "Accept": "application/json",
    "Accept-Encoding": "gzip",
    "Content-Type": "application/json",
  };
}

export interface HotelbedsError {
  code?: string;
  message?: string;
}

export function extractError(data: unknown): string {
  if (typeof data === "object" && data !== null) {
    const d = data as Record<string, unknown>;
    if (d["error"] && typeof d["error"] === "object") {
      const e = d["error"] as HotelbedsError;
      return e.message ?? JSON.stringify(e);
    }
    if (typeof d["message"] === "string") return d["message"];
  }
  return JSON.stringify(data);
}
