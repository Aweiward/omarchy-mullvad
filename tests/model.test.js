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
