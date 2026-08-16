#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v mullvad >/dev/null; then
  echo "SKIP: mullvad not on PATH"
  exit 0
fi

node --input-type=commonjs <<'EOF'
const { execFileSync } = require("node:child_process");
const assert = require("node:assert/strict");
const Model = require("./Model.js");

function run(args) {
  try {
    return { code: 0, out: execFileSync("mullvad", args, { encoding: "utf8" }) };
  } catch (err) {
    return { code: err.status || 1, out: String(err.stdout || "") + String(err.stderr || "") };
  }
}

const status = Model.parseStatusJson(run(["status", "--json"]).out);
assert.ok(["disconnected", "connected", "connecting", "disconnecting", "error"].includes(status.state));
if (status.state === "disconnected") {
  assert.equal(status.locationCity, "");
}

const account = Model.parseAccountGet(run(["account", "get"]).out, run(["account", "get"]).code);
assert.equal(typeof account.loggedIn, "boolean");

const lockdown = Model.parseLockdownGet(run(["lockdown-mode", "get"]).out);
assert.equal(typeof lockdown, "boolean");

const relay = Model.parseRelayGet(run(["relay", "get"]).out);
assert.equal(typeof relay.country, "string");

const cities = Model.parseRelayList(run(["relay", "list"]).out);
assert.ok(cities.length > 10);
assert.ok(cities.every((c) => c.countryCode && c.cityCode && !/-wg-/.test(c.city)));

// The panel logs in by piping the account number to stdin instead of passing it
// as an argv entry, so assert the CLI still prompts for it. A bogus number can
// never log anyone in, so this leaves account state untouched.
const { spawnSync } = require("node:child_process");
const prompt = spawnSync("mullvad", ["account", "login"], {
  input: "0000000000000000\n",
  encoding: "utf8",
  timeout: 30000
});
assert.notEqual(prompt.status, 0);
assert.match(String(prompt.stdout || ""), /account number/i);

console.log("cli-contract ok", {
  state: status.state,
  loggedIn: account.loggedIn,
  cities: cities.length
});
EOF
