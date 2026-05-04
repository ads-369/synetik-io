const http = require("http");
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const root = __dirname;
const dataDir = path.join(root, "data");
const port = Number(process.env.PORT || 4173);

const mimeTypes = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "application/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".svg": "image/svg+xml",
  ".ico": "image/x-icon",
  ".pdf": "application/pdf",
  ".xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
};

fs.mkdirSync(dataDir, { recursive: true });

function sendJson(res, statusCode, payload) {
  res.writeHead(statusCode, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
  });
  res.end(JSON.stringify(payload));
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let raw = "";
    req.on("data", (chunk) => {
      raw += chunk;
      if (raw.length > 1_000_000) {
        reject(new Error("Payload too large"));
        req.destroy();
      }
    });
    req.on("end", () => resolve(raw));
    req.on("error", reject);
  });
}

function appendJsonLine(fileName, payload) {
  const record = {
    id: crypto.randomUUID(),
    receivedAt: new Date().toISOString(),
    ...payload,
  };

  fs.appendFileSync(path.join(dataDir, fileName), `${JSON.stringify(record)}\n`, "utf8");
  return record;
}

function sanitizeLead(payload) {
  const lead = {
    name: String(payload.name || "").trim(),
    email: String(payload.email || "").trim().toLowerCase(),
    interest: String(payload.interest || "").trim(),
    message: String(payload.message || "").trim(),
    sessionId: String(payload.sessionId || "").trim(),
  };

  if (!lead.name || !lead.email || !lead.interest) {
    throw new Error("Missing required lead fields");
  }

  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(lead.email)) {
    throw new Error("Invalid email");
  }

  return lead;
}

async function handleApi(req, res) {
  try {
    const raw = await readBody(req);
    const payload = raw ? JSON.parse(raw) : {};

    if (req.url === "/api/leads" && req.method === "POST") {
      const lead = appendJsonLine("leads.jsonl", sanitizeLead(payload));
      sendJson(res, 201, { ok: true, id: lead.id });
      return;
    }

    if (req.url === "/api/analytics" && req.method === "POST") {
      const event = {
        event: String(payload.event || "unknown").slice(0, 80),
        path: String(payload.path || "/").slice(0, 240),
        title: String(payload.title || "").slice(0, 180),
        sessionId: String(payload.sessionId || "").slice(0, 120),
        timestamp: String(payload.timestamp || new Date().toISOString()),
        label: payload.label ? String(payload.label).slice(0, 160) : undefined,
        href: payload.href ? String(payload.href).slice(0, 240) : undefined,
        referrer: payload.referrer ? String(payload.referrer).slice(0, 320) : undefined,
        viewport: payload.viewport ? String(payload.viewport).slice(0, 32) : undefined,
        interest: payload.interest ? String(payload.interest).slice(0, 120) : undefined,
      };

      appendJsonLine("analytics.jsonl", event);
      sendJson(res, 202, { ok: true });
      return;
    }

    sendJson(res, 404, { ok: false, error: "Endpoint not found" });
  } catch (error) {
    sendJson(res, 400, { ok: false, error: error.message });
  }
}

function serveStatic(req, res) {
  if (req.url === "/health") {
    sendJson(res, 200, { ok: true, service: "synetik-io" });
    return;
  }

  const url = new URL(req.url, `http://${req.headers.host}`);
  const requestedPath = url.pathname === "/" ? "/index.html" : decodeURIComponent(url.pathname);
  const filePath = path.normalize(path.join(root, requestedPath));

  if (!filePath.startsWith(root)) {
    sendJson(res, 403, { ok: false, error: "Forbidden" });
    return;
  }

  fs.readFile(filePath, (error, content) => {
    if (error) {
      res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
      res.end("Not found");
      return;
    }

    const ext = path.extname(filePath).toLowerCase();
    res.writeHead(200, {
      "Content-Type": mimeTypes[ext] || "application/octet-stream",
      "Cache-Control": ext === ".html" ? "no-store" : "public, max-age=3600",
    });
    res.end(content);
  });
}

const server = http.createServer((req, res) => {
  if (req.url.startsWith("/api/")) {
    handleApi(req, res);
    return;
  }

  serveStatic(req, res);
});

server.listen(port, "0.0.0.0", () => {
  console.log(`Synetik.IO running at http://localhost:${port}`);
});
