import { createHash } from "node:crypto";
import { getInfo, getUrl } from "@floot/storage";
import { SecurityError } from "./requestSecurity";

export type MediaFingerprint = {
  etag: string;
  sha256: string;
  sizeBytes: number;
  contentType: string;
};
const MiB = 1024 * 1024;
function invalid(): never {
  throw new SecurityError(
    "Содержимое файла не соответствует формату или файл повреждён.",
  );
}
function dimensions(width: number, height: number) {
  if (
    width < 1 ||
    height < 1 ||
    width > 8192 ||
    height > 8192 ||
    width * height > 25_000_000
  )
    invalid();
}
// A bounded container check, not a decoder or an antivirus. Never execute uploads.
export function checkMediaHeader(data: Buffer, type: string, size: number) {
  if (data.length < 12) invalid();
  if (type === "audio/mpeg") {
    let offset = 0;
    if (data.toString("ascii", 0, 3) === "ID3") {
      if (
        ![2, 3, 4].includes(data[3]) ||
        data.subarray(6, 10).some((b) => b > 127)
      )
        invalid();
      offset =
        10 + ((data[6] << 21) | (data[7] << 14) | (data[8] << 7) | data[9]);
      if (data[3] === 4 && data[5] & 16) offset += 10;
    }
    let frame = false;
    for (let i = offset; i < Math.min(data.length - 3, offset + 8192); i++) {
      if (
        data[i] === 255 &&
        (data[i + 1] & 224) === 224 &&
        (data[i + 1] & 24) !== 8 &&
        (data[i + 1] & 6) !== 0 &&
        (data[i + 2] & 240) !== 0 &&
        (data[i + 2] & 240) !== 240 &&
        (data[i + 2] & 12) !== 12
      ) {
        frame = true;
        break;
      }
    }
    if (!frame) invalid();
  } else if (type === "audio/wav") {
    if (
      data.toString("ascii", 0, 4) !== "RIFF" ||
      data.toString("ascii", 8, 12) !== "WAVE" ||
      data.readUInt32LE(4) + 8 !== size
    )
      invalid();
    let found = false;
    for (let i = 12; i + 8 <= data.length; ) {
      const bytes = data.readUInt32LE(i + 4);
      if (i + 8 + bytes > size) invalid();
      if (
        data.toString("ascii", i, i + 4) === "fmt " &&
        bytes >= 16 &&
        i + 24 <= data.length
      ) {
        if (
          ![1, 3, 0xfffe].includes(data.readUInt16LE(i + 8)) ||
          data.readUInt16LE(i + 10) < 1 ||
          data.readUInt16LE(i + 10) > 8 ||
          data.readUInt32LE(i + 12) < 8000 ||
          data.readUInt32LE(i + 12) > 384000
        )
          invalid();
        found = true;
        break;
      }
      i += 8 + bytes + (bytes % 2);
    }
    if (!found) invalid();
  } else if (type === "audio/mp4" || type === "audio/x-m4a") {
    const length = data.readUInt32BE(0);
    if (
      data.toString("ascii", 4, 8) !== "ftyp" ||
      length < 16 ||
      length > size ||
      length > data.length
    )
      invalid();
    const brands = [data.toString("ascii", 8, 12)];
    for (let i = 16; i + 4 <= length; i += 4)
      brands.push(data.toString("ascii", i, i + 4));
    if (
      !brands.some((b) =>
        ["M4A ", "M4B ", "isom", "iso2", "mp41", "mp42", "qt  "].includes(b),
      )
    )
      invalid();
  } else if (type === "image/png") {
    if (
      !data
        .subarray(0, 8)
        .equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])) ||
      data.length < 24 ||
      data.readUInt32BE(8) !== 13 ||
      data.toString("ascii", 12, 16) !== "IHDR"
    )
      invalid();
    dimensions(data.readUInt32BE(16), data.readUInt32BE(20));
  } else if (type === "image/jpeg") {
    if (data[0] !== 255 || data[1] !== 216) invalid();
    let found = false;
    for (let i = 2; i + 4 <= data.length; ) {
      if (data[i++] !== 255) invalid();
      while (data[i] === 255) i++;
      const marker = data[i++];
      if (marker === 217 || marker === 218) break;
      const length = data.readUInt16BE(i);
      if (length < 2 || i + length > size) invalid();
      if (
        [
          0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd,
          0xce, 0xcf,
        ].includes(marker) &&
        i + 7 <= data.length
      ) {
        dimensions(data.readUInt16BE(i + 5), data.readUInt16BE(i + 3));
        found = true;
        break;
      }
      i += length;
    }
    if (!found) invalid();
  } else if (type === "image/webp") {
    if (
      data.toString("ascii", 0, 4) !== "RIFF" ||
      data.toString("ascii", 8, 12) !== "WEBP" ||
      data.readUInt32LE(4) + 8 !== size ||
      data.length < 30
    )
      invalid();
    const kind = data.toString("ascii", 12, 16);
    if (kind === "VP8X")
      dimensions(1 + data.readUIntLE(24, 3), 1 + data.readUIntLE(27, 3));
    else if (
      kind === "VP8 " &&
      data.subarray(23, 26).equals(Buffer.from([157, 1, 42]))
    )
      dimensions(
        data.readUInt16LE(26) & 0x3fff,
        data.readUInt16LE(28) & 0x3fff,
      );
    else if (kind === "VP8L" && data[20] === 47)
      dimensions(
        1 + (data.readUInt32LE(21) & 0x3fff),
        1 + ((data.readUInt32LE(21) >>> 14) & 0x3fff),
      );
    else invalid();
  } else if (type !== "application/json") invalid();
}

export async function inspectStoredMedia(
  visibility: "private" | "public",
  filename: string,
  part: "audio" | "cover" | "submission",
  expectedSize?: number,
  expectedType?: string,
) {
  const info = await getInfo({ visibility, filename });
  const limit =
    part === "audio" ? 100 * MiB : part === "cover" ? 10 * MiB : 256 * 1024;
  if (
    !info.ok ||
    !info.exists ||
    info.sizeBytes <= 0 ||
    info.sizeBytes > limit ||
    (expectedSize !== undefined && info.sizeBytes !== expectedSize)
  )
    throw new SecurityError(
      "Файл ещё не загружен полностью или превышает лимит.",
    );
  const etag = "etag" in info && typeof info.etag === "string" ? info.etag : "";
  if (!etag) throw new SecurityError("Хранилище не вернуло версию файла.", 503);
  const source = await getUrl({ visibility, filename, expiresInSeconds: 120 });
  if (!source.ok || new URL(source.url).protocol !== "https:")
    throw new SecurityError("Файл недоступен.", 503);
  // Only SDK-issued URLs for an already owned storage key; no URL supplied by the client.
  const response = await fetch(source.url, {
    headers: { "If-Match": etag.startsWith('"') ? etag : `"${etag}"` },
    redirect: "error",
    signal: AbortSignal.timeout(60000),
  });
  if (!response.ok || !response.body)
    throw new SecurityError("Файл изменён или недоступен.", 409);
  const hash = createHash("sha256"),
    reader = response.body.getReader();
  const chunks: Buffer[] = [];
  let size = 0,
    retained = 0;
  const probeLimit = part === "audio" ? 6 * MiB : limit;
  try {
    while (true) {
      const next = await reader.read();
      if (next.done) break;
      size += next.value.byteLength;
      if (size > info.sizeBytes || size > limit) {
        await reader.cancel();
        throw new SecurityError("Файл превышает заявленный размер.");
      }
      hash.update(next.value);
      if (retained < probeLimit) {
        const bytes = Buffer.from(
          next.value.subarray(0, probeLimit - retained),
        );
        chunks.push(bytes);
        retained += bytes.length;
      }
    }
  } finally {
    reader.releaseLock();
  }
  if (size !== info.sizeBytes)
    throw new SecurityError("Файл загружен не полностью.");
  const data = Buffer.concat(chunks),
    contentType =
      expectedType ?? (part === "submission" ? "application/json" : "");
  checkMediaHeader(data, contentType, size);
  let json: unknown;
  if (part === "submission") {
    try {
      json = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(data));
    } catch {
      throw new SecurityError("Некорректная заявка публикации.");
    }
  }
  return {
    fingerprint: {
      etag,
      sha256: hash.digest("hex"),
      sizeBytes: size,
      contentType,
    } satisfies MediaFingerprint,
    json,
  };
}

export function catalogueMediaURL(
  trackId: string,
  part: "audio" | "cover",
  filename: string,
) {
  const version = createHash("sha256")
    .update(filename)
    .digest("hex")
    .slice(0, 32);
  return `https://muwa-app.floot.app/_api/catalog/media?trackId=${encodeURIComponent(trackId)}&part=${part}&v=${version}`;
}
