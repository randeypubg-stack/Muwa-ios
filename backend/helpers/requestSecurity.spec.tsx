import {
  guardMutation,
  readJSONLimited,
  SecurityError,
} from "./requestSecurity";
describe("Muwa bounded request parsing", () => {
  it("rejects oversized bodies with and without Content-Length", async () => {
    for (const headers of [{}, { "Content-Length": "9999" }]) {
      const request = new Request("https://muwa-app.floot.app/", {
        method: "POST",
        headers,
        body: JSON.stringify({ text: "ع".repeat(1024) }),
      });
      try {
        await readJSONLimited(request, 128);
        fail("Oversized body accepted");
      } catch (error) {
        expect(error instanceof SecurityError).toBeTrue();
        expect((error as SecurityError).status).toBe(413);
      }
    }
  });
  it("checks MIME and origin before mutation, including cross-site requests without Origin", () => {
    for (const headers of [
      { "Content-Type": "text/plain" },
      {
        "Content-Type": "application/json",
        Origin: "https://attacker.invalid",
      },
      { "Content-Type": "application/json", "Sec-Fetch-Site": "cross-site" },
    ])
      expect(() =>
        guardMutation(
          new Request("https://muwa-app.floot.app/", {
            method: "POST",
            headers,
            body: "{}",
          }),
        ),
      ).toThrow();
    expect(() =>
      guardMutation(
        new Request("https://muwa-app.floot.app/", {
          method: "POST",
          headers: { "Content-Type": "application/json; charset=utf-8" },
          body: "{}",
        }),
      ),
    ).not.toThrow();
  });
  it("rejects invalid UTF-8 and accepts a bounded JSON body", async () => {
    await expectAsync(
      readJSONLimited(
        new Request("https://muwa-app.floot.app/", {
          method: "POST",
          body: Uint8Array.from([255, 255]),
        }),
        64,
      ),
    ).toBeRejected();
    expect(
      await readJSONLimited(
        new Request("https://muwa-app.floot.app/", {
          method: "POST",
          body: '{"value":1}',
        }),
        64,
      ),
    ).toEqual({ value: 1 });
  });
});
