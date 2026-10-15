const assert = require("node:assert/strict");
const fs = require("node:fs");
const http = require("node:http");
const os = require("node:os");
const path = require("node:path");
const { spawn } = require("node:child_process");

async function main() {
  const executable = process.argv[2];
  assert.ok(executable, "Supply the packaged PerformanceAnalyzer.Mcp.exe.");
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "pa-connection-diagnostic-"));
  let mode = "valid";
  const marker = "diagnostic-secret-fixture-73ac";
  const server = http.createServer((request, response) => {
    response.setHeader("Content-Type", "application/json");
    if (mode === "rejected") {
      response.writeHead(403);
      response.end(JSON.stringify({ error: `Rejected fixture ${marker}` }));
      return;
    }
    response.end(JSON.stringify({
      CaptureId: "diagnostic-fixture", FileName: "fixture.blg", SessionMode: "BLG",
      StartMilliseconds: 1000, EndMilliseconds: 2000, Sources: {},
      Counters: [], Mapping: mode === "invalid" ? { Disks: "not-an-array" } : {
        Disks: [{ DiskNumber: 1, PerfmonPhysicalInstances: ["1 D:"],
          Partitions: [{ DriveLetter: "D:", PartitionNumber: 1 }] }]
      }
    }));
  });
  const run = () => new Promise((resolve, reject) => {
    const child = spawn("powershell.exe", [
      "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
      path.join(__dirname, "..", "scripts", "Test-CopilotConnection.ps1")
    ], {
      env: { ...process.env, COPILOT_HOME: root },
      stdio: ["ignore", "pipe", "pipe"]
    });
    let output = "";
    for (const stream of [child.stdout, child.stderr]) {
      stream.on("data", data => { output += data.toString(); });
    }
    const timeout = setTimeout(() => { child.kill(); reject(new Error("Diagnostic timed out.")); }, 90000);
    child.on("error", error => { clearTimeout(timeout); reject(error); });
    child.on("exit", code => { clearTimeout(timeout); resolve({ code, output }); });
  });
  try {
    await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
    const config = JSON.stringify({ mcpServers: {
      "performance-analyzer": {
        type: "local", command: path.resolve(executable),
        args: ["--endpoint", `http://127.0.0.1:${server.address().port}/`, "--timeout-seconds", "3"],
        env: { PA_DIAGNOSTIC_TEST_SECRET: marker }
      }
    } });
    const configPath = path.join(root, "mcp-config.json");
    fs.writeFileSync(configPath, config);
    const valid = await run();
    assert.equal(valid.code, 0, valid.output);
    for (const tool of ["get_server_status", "get_capture_overview", "get_capture_health",
      "get_coach_status", "get_coach_targets"]) {
      assert.ok(valid.output.includes(`${tool}: succeeded.`), valid.output);
    }
    assert.equal(fs.readFileSync(configPath, "utf8"), config, "Diagnostic never edits registration.");
    mode = "invalid";
    const invalid = await run();
    assert.notEqual(invalid.code, 0, invalid.output);
    assert.match(invalid.output, /MCP stderr/);
    assert.match(invalid.output, /JsonException|JSON/);
    assert.match(invalid.output, /Mapping\.Disks/);
    mode = "rejected";
    const rejected = await run();
    assert.notEqual(rejected.code, 0, rejected.output);
    assert.match(rejected.output, /Rejected fixture \[REDACTED\]/);
    assert.ok(!rejected.output.includes(marker), "Secret registration values must be redacted from exceptions.");
    await new Promise(resolve => server.close(resolve));
    const unavailable = await run();
    assert.notEqual(unavailable.code, 0, unavailable.output);
    assert.match(unavailable.output, /unavailable at|SocketException|actively refused/);
    assert.equal(fs.readFileSync(configPath, "utf8"), config);
    console.log("PASS: five read-only tools, invalid metadata JSON path, rejected API, unreachable endpoint, secret redaction and unchanged configuration.");
  } finally {
    if (server.listening) await new Promise(resolve => server.close(resolve));
    fs.rmSync(root, { recursive: true, force: true });
  }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
