const MiB = 1024 * 1024;
const compressed = (name) => /\.(zip|kmz|gz|tgz)$/i.test(name);
const check = (signal) => {
  if (signal?.aborted) throw new DOMException("Aborted", "AbortError");
};

export async function prepareFile(
  file,
  {
    signal,
    maxOriginal = 256 * MiB,
    maxWorking = 64 * MiB,
    chunkSize = 2 * MiB,
    onProgress = () => {},
    onBuffered = () => {},
  } = {},
) {
  const raw = {
    file,
    originalFilename: file.name,
    originalSize: file.size,
    clientWrapped: false,
  };
  check(signal);
  if (compressed(file.name)) return raw;
  if (file.size > maxOriginal) return { ...raw, fallback: "size" };
  try {
    const { Zip, ZipDeflate } = await import("fflate");
    check(signal);
    const chunks = [];
    let retained = 0;
    const zip = new Zip((error, chunk) => {
      if (error) throw error;
      retained += chunk.byteLength;
      const working = retained * 3 + chunkSize * 2;
      if (working > maxWorking) throw new Error("Preparation budget");
      onBuffered(working);
      chunks.push(chunk);
    });
    const entry = new ZipDeflate(file.name, { level: 6 });
    zip.add(entry);
    for (let offset = 0; offset < file.size; offset += chunkSize) {
      check(signal);
      const bytes = new Uint8Array(
        await file.slice(offset, offset + chunkSize).arrayBuffer(),
      );
      check(signal);
      entry.push(bytes, offset + chunkSize >= file.size);
      onProgress(
        Math.min(100, Math.round(((offset + chunkSize) * 100) / file.size)),
      );
      await new Promise((resolve) => setTimeout(resolve, 0));
    }
    check(signal);
    zip.end();
    return {
      ...raw,
      file: new File(chunks, `${file.name}.zip`, { type: "application/zip" }),
      clientWrapped: true,
    };
  } catch (error) {
    check(signal);
    if (error.name === "AbortError") throw error;
    return { ...raw, fallback: "compression" };
  }
}
