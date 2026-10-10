import { telegramImportOwnerAllowed } from "./runtimeConfig";

describe("Telegram import owner authorization", () => {
  let original: string | undefined;
  beforeEach(() => { original = process.env.MUWA_TELEGRAM_OWNER_ID; });
  afterEach(() => {
    if (original === undefined) delete process.env.MUWA_TELEGRAM_OWNER_ID;
    else process.env.MUWA_TELEGRAM_OWNER_ID = original;
  });
  it("denies everyone when the server has no valid owner configuration", () => {
    for (const value of [undefined, "", "0", "-1", "1,2", "01", "1.0", " 1", "Infinity", "9007199254740992"]) {
      if (value === undefined) delete process.env.MUWA_TELEGRAM_OWNER_ID;
      else process.env.MUWA_TELEGRAM_OWNER_ID = value;
      expect(telegramImportOwnerAllowed(1)).toBeFalse();
    }
  });
  it("grants exactly the configured authenticated user ID", () => {
    process.env.MUWA_TELEGRAM_OWNER_ID = "17";
    expect(telegramImportOwnerAllowed(17)).toBeTrue();
    for (const id of [1, 2, 0, -1, 17.1, NaN, Infinity])
      expect(telegramImportOwnerAllowed(id)).toBeFalse();
  });
});
