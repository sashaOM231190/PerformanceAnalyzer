const fs = require("node:fs");
const path = require("node:path");
const assert = require("node:assert/strict");

const args = process.argv.slice(2);
const root = process.env.PA_PACKAGE_TEST_ROOT;
assert.ok(root, "This stub runs only inside the isolated packaging fixture.");
fs.appendFileSync(path.join(root, "calls.jsonl"), JSON.stringify(args) + "\n");
if (args[0] === "winget") {
  assert.deepEqual(args.slice(1), ["install", "--id", "GitHub.Copilot", "--exact", "--source", "winget"]);
  if (process.env.PA_PACKAGE_TEST_WINGET_FAIL) process.exit(5);
  fs.copyFileSync(path.join(root, "copilot-template.cmd"), path.join(root, "bin", "copilot.cmd"));
  process.exit(0);
}
const configPath = path.join(process.env.COPILOT_HOME ||
  path.join(process.env.USERPROFILE, ".copilot"), "mcp-config.json");
const config = fs.existsSync(configPath)
  ? JSON.parse(fs.readFileSync(configPath, "utf8").replace(/^\uFEFF/, ""))
  : { mcpServers: {} };
config.mcpServers ||= {};
assert.equal(args[0], "mcp");
assert.equal(args[2], "performance-analyzer");
switch (args[1]) {
  case "remove":
    assert.ok(config.mcpServers["performance-analyzer"]);
    delete config.mcpServers["performance-analyzer"];
    break;
  case "add": {
    if (process.env.PA_PACKAGE_TEST_ADD_FAIL) process.exit(9);
    assert.equal(config.mcpServers["performance-analyzer"], undefined);
    assert.equal(args[3], "--env");
    assert.equal(args[5], "--");
    const endpoint = args[4].split("=").slice(1).join("=");
    config.mcpServers["performance-analyzer"] = {
      type: "local", command: args[6], args: [],
      env: { PERFORMANCEANALYZER_ENDPOINT: endpoint }
    };
    break;
  }
  case "get":
    if (!config.mcpServers["performance-analyzer"]) process.exit(1);
    console.log("Fixture registration verified.");
    process.exit(0);
  default:
    throw new Error("Unexpected fixture command.");
}
fs.mkdirSync(path.dirname(configPath), { recursive: true });
fs.writeFileSync(configPath, JSON.stringify(config));
