import assert from "node:assert/strict";
import { test } from "node:test";
import { PulseMeshClient, PulseMeshApiError } from "../dist/index.js";

const client = new PulseMeshClient(
  "https://api.example.test",
  () => "default-token",
);

for (const [name, headers] of [
  ["object", { "x-workspace-id": "workspace" }],
  ["Headers", new Headers({ "x-workspace-id": "workspace" })],
  ["tuples", [["x-workspace-id", "workspace"]]],
]) {
  test(`preserves ${name} headers alongside SDK defaults`, async (t) => {
    t.mock.method(globalThis, "fetch", async (_url, init) => {
      const actual = new Headers(init.headers);
      assert.equal(actual.get("x-workspace-id"), "workspace");
      assert.equal(actual.get("authorization"), "Bearer default-token");
      assert.equal(actual.get("content-type"), "application/json");
      return Response.json({ ok: true });
    });
    assert.deepEqual(await client.request("/test", { headers }), { ok: true });
  });
}

test("caller headers override defaults case-insensitively", async (t) => {
  t.mock.method(globalThis, "fetch", async (_url, init) => {
    const headers = new Headers(init.headers);
    assert.equal(headers.get("authorization"), "Bearer override");
    assert.equal(headers.get("content-type"), "application/problem+json");
    return Response.json({ ok: true });
  });
  await client.request("/test", {
    headers: {
      Authorization: "Bearer override",
      "Content-Type": "application/problem+json",
    },
  });
});

test("successful no-content responses do not cause JSON parse failures", async (t) => {
  t.mock.method(globalThis, "fetch", async (_url, init) => {
    assert.equal(init.method, "DELETE");
    return new Response(null, { status: 204 });
  });
  assert.equal(
    await client.request("/messages/id/bookmark", { method: "DELETE" }),
    undefined,
  );
});

test("JSON responses and request bodies are preserved", async (t) => {
  t.mock.method(globalThis, "fetch", async (url, init) => {
    assert.equal(url, "https://api.example.test/test");
    assert.equal(init.method, "POST");
    assert.equal(init.body, '{"name":"test"}');
    return Response.json({ id: "created" });
  });
  assert.deepEqual(
    await client.request("/test", { method: "POST", body: '{"name":"test"}' }),
    { id: "created" },
  );
});

test("structured API failures remain typed", async (t) => {
  t.mock.method(globalThis, "fetch", async () =>
    Response.json(
      {
        error: {
          code: "FORBIDDEN",
          message: "Access denied",
          requestId: "req-1",
        },
      },
      { status: 403 },
    ),
  );
  await assert.rejects(
    client.request("/test"),
    (error) =>
      error instanceof PulseMeshApiError &&
      error.code === "FORBIDDEN" &&
      error.requestId === "req-1",
  );
});
