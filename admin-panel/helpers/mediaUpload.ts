export function mime(file: File) {
  return (
    file.type ||
    (
      {
        mp3: "audio/mpeg",
        m4a: "audio/mp4",
        wav: "audio/wav",
        jpg: "image/jpeg",
        jpeg: "image/jpeg",
        png: "image/png",
        webp: "image/webp",
      } as Record<string, string>
    )[file.name.split(".").pop()?.toLowerCase() ?? ""] ||
    ""
  );
}
export async function audioDuration(file: Blob) {
  return new Promise<number>((resolve, reject) => {
    const url = URL.createObjectURL(file),
      audio = new Audio();
    const done = () => {
      clearTimeout(timer);
      audio.removeAttribute("src");
      audio.load();
      URL.revokeObjectURL(url);
    };
    const timer = setTimeout(() => {
      done();
      reject(new Error("Не удалось определить длительность аудио."));
    }, 15000);
    audio.preload = "metadata";
    audio.onloadedmetadata = () => {
      const duration = audio.duration;
      done();
      if (Number.isFinite(duration) && duration > 0) resolve(duration);
      else reject(new Error("Проверьте формат аудио."));
    };
    audio.onerror = () => {
      done();
      reject(new Error("Этот аудиофайл не читается."));
    };
    audio.src = url;
  });
}
export async function put(
  url: string,
  headers: Record<string, string>,
  file: Blob,
) {
  const r = await fetch(url, { method: "PUT", headers, body: file });
  if (!r.ok)
    throw new Error("Файл не загрузился. Проверьте соединение и повторите.");
}
