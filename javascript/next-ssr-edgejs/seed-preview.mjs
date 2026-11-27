import { mkdirSync, writeFileSync } from "node:fs";

// Next 16.1.7 reads this cache before generating random draft-mode keys.
// These public values are only used by the local compatibility fixture.
mkdirSync(".next/cache", { recursive: true });
writeFileSync(".next/cache/.previewinfo", JSON.stringify({
  previewModeId: "01".repeat(16),
  previewModeSigningKey: "02".repeat(32),
  previewModeEncryptionKey: "03".repeat(32),
  expireAt: Number.MAX_SAFE_INTEGER,
}));
