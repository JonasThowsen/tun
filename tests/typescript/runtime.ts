// runtime.ts -- runs the fixture's module in Node against a stand-in fetch
// and document, and prints what each kind of answer became, as JSON, for
// tests/typescript-tests.lisp.  Nothing leaves the process.

import { tsNotesClose, tsNotesCreate, tsNotesRaw } from "./api.js";

type Seen = {
  url: string;
  method: string;
  credentials: string;
  headers: { [name: string]: string };
  body: unknown;
};

const seen: Seen[] = [];
let next: () => Promise<Response> = async () => new Response("{}");

Object.defineProperty(globalThis, "document", {
  value: {
    querySelector: (selector: string) =>
      selector === 'meta[name="tun-api-proof"]'
        ? { getAttribute: (name: string) => (name === "content" ? "PROOF" : null) }
        : null,
  },
});

Object.defineProperty(globalThis, "fetch", {
  value: async (url: string, init: RequestInit) => {
    seen.push({
      url,
      method: String(init.method),
      credentials: String(init.credentials),
      headers: { ...(init.headers as { [name: string]: string }) },
      body: JSON.parse(String(init.body)),
    });
    if (init.signal?.aborted) throw new DOMException("The call was aborted", "AbortError");
    return next();
  },
});

function json(status: number, body: unknown): () => Promise<Response> {
  return async () =>
    new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

const results: { [name: string]: unknown } = {};

next = json(200, { id: "tsn_1", title: "Milk" });
results["ok"] = await tsNotesCreate({ title: "Milk" });
results["request"] = seen[0];

next = json(200, {
  confirmation_required: true, confirmation_token: "tok", expires_at: "2026-11-17T10:00:00Z",
  summary: "Close Milk",
});
results["confirm"] = await tsNotesClose({ id: "tsn_1" });
results["notConfirmable"] = await tsNotesRaw();

next = json(422, {
  error: {
    code: "invalid_input", message: "Invalid input",
    fields: [
      { field: "title", message: "must be filled in" },
      { field: "title", message: "is too long" },
      { field: "status", message: "must be one of: open, closed" },
    ],
    expected_revision: 3,
  },
});
results["refused"] = await tsNotesCreate({ title: "" });

next = async () => { throw new TypeError("fetch failed"); };
results["network"] = await tsNotesCreate({ title: "Milk" });

const controller = new AbortController();
controller.abort();
next = json(200, {});
results["aborted"] = await tsNotesCreate({ title: "Milk" }, { signal: controller.signal });

next = async () => new Response("<html>Bad gateway</html>", { status: 502 });
results["notJson"] = await tsNotesCreate({ title: "Milk" });

next = json(500, { oops: 1 });
results["noDocument"] = await tsNotesCreate({ title: "Milk" });

next = json(400, { error: { code: "nonsense", message: "?" } });
results["unknownCode"] = await tsNotesCreate({ title: "Milk" });

console.log(JSON.stringify(results));
