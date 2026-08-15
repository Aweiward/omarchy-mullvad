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
