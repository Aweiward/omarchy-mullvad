const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const Model = require("../Model.js");

const relayList = fs.readFileSync(
  path.join(__dirname, "fixtures/relay-list.txt"),
  "utf8"
);

test("parseRelayList returns one row per country+city and drops hostnames", () => {
  const cities = Model.parseRelayList(relayList);
  assert.deepEqual(cities, [
    { country: "Albania", countryCode: "al", city: "Tirana", cityCode: "tia" },
    { country: "Sweden", countryCode: "se", city: "Gothenburg", cityCode: "got" },
    { country: "Sweden", countryCode: "se", city: "Malmö", cityCode: "mma" },
    { country: "United States", countryCode: "us", city: "New York", cityCode: "nyc" }
  ]);
});

test("parseRelayList returns [] for empty or garbage stdout", () => {
  assert.deepEqual(Model.parseRelayList(""), []);
  assert.deepEqual(Model.parseRelayList(null), []);
  assert.deepEqual(Model.parseRelayList("error: daemon is offline"), []);
});

test("filterCities matches country, city, and codes case-insensitively", () => {
  const cities = Model.parseRelayList(relayList);
  const got = Model.filterCities(cities, "got");
  assert.equal(got.length, 1);
  assert.equal(got[0].city, "Gothenburg");

  const sweden = Model.filterCities(cities, "se");
  assert.equal(sweden.length, 2);
  assert.equal(sweden[0].countryCode, "se");
  assert.equal(sweden[1].countryCode, "se");

  const nyc = Model.filterCities(cities, "new yo");
  assert.equal(nyc.length, 1);
  assert.equal(nyc[0].cityCode, "nyc");
});

test("filterCities with blank query returns every city", () => {
  const cities = Model.parseRelayList(relayList);
  assert.equal(Model.filterCities(cities, "  ").length, cities.length);
});

test("mergeRecentCities puts remembered keys first without duplicating", () => {
  const cities = Model.parseRelayList(relayList);
  const merged = Model.mergeRecentCities(["us nyc", "se got"], cities);
  assert.equal(merged[0].cityCode, "nyc");
  assert.equal(merged[1].cityCode, "got");
  assert.equal(merged.length, cities.length);
});

test("normalizeAccountNumber strips spaces and requires 16 digits", () => {
  assert.deepEqual(Model.normalizeAccountNumber("1234 5678 9012 3456"), {
    ok: true,
    digits: "1234567890123456",
    error: ""
  });
  assert.equal(Model.normalizeAccountNumber("123").ok, false);
  assert.equal(Model.normalizeAccountNumber("abcdefghijklmnop").ok, false);
  assert.equal(Model.normalizeAccountNumber("").error, "Enter your 16-digit account number.");
});

test("parseStatusJson ignores visible location when disconnected", () => {
  const raw = fs.readFileSync(
    path.join(__dirname, "fixtures/status-disconnected.json"),
    "utf8"
  );
  const status = Model.parseStatusJson(raw);
  assert.equal(status.ignored, false);
  assert.equal(status.state, "disconnected");
  assert.equal(status.active, false);
  assert.equal(status.locationCountry, "");
  assert.equal(status.locationCity, "");
  assert.equal(status.mullvadExitIp, false);
  assert.equal(status.lockedDown, false);
});

test("parseStatusJson uses location only when connected", () => {
  const raw = JSON.stringify({
    state: "connected",
    details: {
      location: {
        country: "Sweden",
        city: "Gothenburg",
        mullvad_exit_ip: true,
        hostname: "se-got-wg-001"
      },
      locked_down: false
    }
  });
  const status = Model.parseStatusJson(raw);
  assert.equal(status.ignored, false);
  assert.equal(status.state, "connected");
  assert.equal(status.active, true);
  assert.equal(status.locationCountry, "Sweden");
  assert.equal(status.locationCity, "Gothenburg");
  assert.equal(status.mullvadExitIp, true);
});

test("parseStatusJson returns error state for garbage", () => {
  const status = Model.parseStatusJson("not-json");
  assert.equal(status.state, "error");
  assert.equal(status.active, false);
});

test("parseStatusJson ignores listen events that have no tunnel state", () => {
  const status = Model.parseStatusJson('{"type":"settings"}');
  assert.equal(status.ignored, true);
  assert.equal(status.state, "");
  assert.equal(status.active, false);
  assert.notEqual(status.state, "error");
});

test("parseAccountGet reads expiry and device", () => {
  const raw = [
    "Mullvad account:    0000000000000000",
    "Expires at:         2026-09-12 20:25:29 -04:00",
    "Device name:        Deep Robin"
  ].join("\n");
  const account = Model.parseAccountGet(raw, 0);
  assert.equal(account.loggedIn, true);
  assert.equal(account.deviceName, "Deep Robin");
  assert.equal(account.accountExpiry, "2026-09-12");
  assert.equal(account.error, "");
});

test("parseAccountGet treats non-zero exit as logged out", () => {
  const account = Model.parseAccountGet("Not logged in", 1);
  assert.equal(account.loggedIn, false);
  assert.equal(account.deviceName, "");
});

test("parseAccountGet treats a revoked device as logged out without leaking the number", () => {
  const account = Model.parseAccountGet(
    "The current device has been revoked\nMullvad account: 0000000000000000",
    0
  );
  assert.equal(account.loggedIn, false);
  assert.match(account.error, /revoked/i);
  assert.equal(/\d{16}/.test(account.error), false);
});

test("parseAccountGet treats account number with failed expiry fetch as logged in", () => {
  // mullvad account get prints the number, then fetches expiry from the API.
  // At boot that API call often fails, so the CLI exits 1 after:
  //   Mullvad account:    0000000000000000
  const account = Model.parseAccountGet("Mullvad account:    0000000000000000", 1);
  assert.equal(account.loggedIn, true);
  assert.equal(account.accountExpiry, "");
  assert.equal(account.deviceName, "");
  assert.equal(account.error, "");
});

test("nextAccountError drops a stale read error after a successful account parse", () => {
  const failed = Model.parseAccountGet("error: daemon is offline", 1);
  const stale = Model.nextAccountError(failed, "");
  assert.equal(stale, "error: daemon is offline");

  const ok = Model.parseAccountGet(
    [
      "Mullvad account:    0000000000000000",
      "Expires at:         2026-09-12 20:25:29 -04:00",
      "Device name:        Deep Robin"
    ].join("\n"),
    0
  );
  assert.equal(ok.loggedIn, true);
  assert.equal(Model.nextAccountError(ok, stale), "");
});

test("parseAccountGet strips 16-digit sequences from generic errors", () => {
  const account = Model.parseAccountGet("command failed for 1234567890123456", 1);
  assert.equal(account.loggedIn, false);
  assert.equal(account.error.includes("1234567890123456"), false);
  assert.equal(/\d{16}/.test(account.error), false);
});

test("parseLockdownGet reads on/off", () => {
  assert.equal(
    Model.parseLockdownGet("Block traffic when the VPN is disconnected: off"),
    false
  );
  assert.equal(
    Model.parseLockdownGet("Block traffic when the VPN is disconnected: on"),
    true
  );
});

test("parseAutoConnectGet reads on/off", () => {
  assert.equal(Model.parseAutoConnectGet("Autoconnect: off"), false);
  assert.equal(Model.parseAutoConnectGet("Autoconnect: on"), true);
  assert.equal(Model.parseAutoConnectGet(""), false);
});

test("parseLanGet reads allow/block", () => {
  assert.equal(Model.parseLanGet("Local network sharing setting: block"), false);
  assert.equal(Model.parseLanGet("Local network sharing setting: allow"), true);
  assert.equal(Model.parseLanGet(""), false);
});

const dnsGetDefault = [
  "Custom DNS: no",
  "Block ads: false",
  "Block trackers: false",
  "Block malware: true",
  "Block adult content: false",
  "Block gambling: false",
  "Block social media: false"
].join("\n");

test("parseDnsGet reads custom flag and block categories", () => {
  const dns = Model.parseDnsGet(dnsGetDefault);
  assert.deepEqual(dns, {
    custom: false,
    blockAds: false,
    blockTrackers: false,
    blockMalware: true,
    blockAdultContent: false,
    blockGambling: false,
    blockSocialMedia: false
  });
});

test("parseDnsGet flags custom DNS", () => {
  const dns = Model.parseDnsGet("Custom DNS: yes\nServers:\n\t1.1.1.1");
  assert.equal(dns.custom, true);
});

test("parseDnsGet returns null when output is unrecognizable", () => {
  assert.equal(Model.parseDnsGet(""), null);
  assert.equal(Model.parseDnsGet(null), null);
  assert.equal(Model.parseDnsGet("error: daemon is offline"), null);
});

test("buildDnsSetArgs sets ads+trackers and preserves other categories", () => {
  const dns = Model.parseDnsGet(dnsGetDefault);
  assert.deepEqual(Model.buildDnsSetArgs(dns, true), [
    "dns", "set", "default",
    "--block-ads", "--block-trackers", "--block-malware"
  ]);
});

test("buildDnsSetArgs clears only ads+trackers when toggled off", () => {
  const dns = Model.parseDnsGet(
    dnsGetDefault.replace("Block ads: false", "Block ads: true")
      .replace("Block trackers: false", "Block trackers: true")
      .replace("Block gambling: false", "Block gambling: true")
  );
  assert.deepEqual(Model.buildDnsSetArgs(dns, false), [
    "dns", "set", "default",
    "--block-malware", "--block-gambling"
  ]);
});

test("daysUntilExpiry counts calendar days from now to the expiry date", () => {
  const now = new Date(2026, 7, 17, 23, 30);
  assert.equal(Model.daysUntilExpiry("2026-08-24", now), 7);
  assert.equal(Model.daysUntilExpiry("2026-08-17", now), 0);
  assert.equal(Model.daysUntilExpiry("2026-08-16", now), -1);
  assert.equal(Model.daysUntilExpiry("2026-09-17", now), 31);
});

test("daysUntilExpiry treats missing or malformed expiry as unknown", () => {
  const now = new Date(2026, 7, 17);
  assert.equal(Model.daysUntilExpiry("", now), null);
  assert.equal(Model.daysUntilExpiry(null, now), null);
  assert.equal(Model.daysUntilExpiry("soon", now), null);
});

test("expiryWarningText spells out expired, today, tomorrow, and N days", () => {
  assert.equal(Model.expiryWarningText(null), "");
  assert.equal(Model.expiryWarningText(-3), "Account expired");
  assert.equal(Model.expiryWarningText(0), "Account expires today");
  assert.equal(Model.expiryWarningText(1), "Account expires tomorrow");
  assert.equal(Model.expiryWarningText(6), "Account expires in 6 days");
});

test("parseRelayGet reads country and optional city", () => {
  const countryOnly = Model.parseRelayGet("    Location:               country se");
  assert.deepEqual(countryOnly, { country: "se", city: "" });
  const both = Model.parseRelayGet("    Location:               country se city got");
  assert.deepEqual(both, { country: "se", city: "got" });
});
