function parseRelayList(raw) {
  var text = String(raw || "");
  if (text === "") return [];
  var lines = text.split(/\r?\n/);
  var cities = [];
  var country = "";
  var countryCode = "";
  var seen = {};

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    if (!line) continue;

    if (!/^\s/.test(line)) {
      var countryMatch = line.match(/^(.+?)\s+\(([a-z]{2})\)\s*$/);
      if (countryMatch) {
        country = countryMatch[1];
        countryCode = countryMatch[2];
      }
      continue;
    }

    var cityMatch = line.match(/^\s+(.+?)\s+\(([a-z]{3})\)\s+@/);
    if (!cityMatch || countryCode === "") continue;
    var key = countryCode + " " + cityMatch[2];
    if (seen[key]) continue;
    seen[key] = true;
    cities.push({
      country: country,
      countryCode: countryCode,
      city: cityMatch[1],
      cityCode: cityMatch[2]
    });
  }

  return cities;
}

function filterCities(cities, query) {
  return cities || [];
}

function normalizeAccountNumber(raw) {
  return { ok: false, digits: "", error: "Enter your 16-digit account number." };
}

function parseStatusJson(raw) {
  return {
    state: "error",
    active: false,
    locationCountry: "",
    locationCity: "",
    lockedDown: false,
    mullvadExitIp: false
  };
}

function parseAccountGet(raw, exitCode) {
  return { loggedIn: false, accountExpiry: "", deviceName: "", error: "" };
}

function parseLockdownGet(raw) {
  return false;
}

function parseRelayGet(raw) {
  return { country: "", city: "" };
}

function mergeRecentCities(recentKeys, cities) {
  return cities || [];
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    parseRelayList: parseRelayList,
    filterCities: filterCities,
    normalizeAccountNumber: normalizeAccountNumber,
    parseStatusJson: parseStatusJson,
    parseAccountGet: parseAccountGet,
    parseLockdownGet: parseLockdownGet,
    parseRelayGet: parseRelayGet,
    mergeRecentCities: mergeRecentCities
  };
}
