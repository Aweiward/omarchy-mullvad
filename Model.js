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
  var list = cities || [];
  var needle = String(query || "").trim().toLowerCase();
  if (needle === "") return list.slice();
  var out = [];
  for (var i = 0; i < list.length; i++) {
    var row = list[i];
    var hay = [
      row.country,
      row.countryCode,
      row.city,
      row.cityCode,
      row.country + " " + row.city,
      row.countryCode + " " + row.cityCode
    ].join("\n").toLowerCase();
    if (hay.indexOf(needle) !== -1) out.push(row);
  }
  return out;
}

function normalizeAccountNumber(raw) {
  var digits = String(raw || "").replace(/\D/g, "");
  if (digits.length === 16) return { ok: true, digits: digits, error: "" };
  return { ok: false, digits: digits, error: "Enter your 16-digit account number." };
}

function emptyStatus(state) {
  return {
    ignored: false,
    state: state || "error",
    active: false,
    locationCountry: "",
    locationCity: "",
    lockedDown: false,
    mullvadExitIp: false
  };
}

function parseStatusJson(raw) {
  var parsed;
  try {
    parsed = JSON.parse(String(raw || ""));
  } catch (e) {
    return emptyStatus("error");
  }
  if (!parsed || typeof parsed !== "object") return emptyStatus("error");
  if (typeof parsed.state !== "string") {
    return {
      ignored: true,
      state: "",
      active: false,
      locationCountry: "",
      locationCity: "",
      lockedDown: false,
      mullvadExitIp: false
    };
  }

  var state = parsed.state;
  var details = parsed.details || {};
  var location = details.location || {};
  var exitIp = location.mullvad_exit_ip === true;
  var tunnelOpen = state === "connected" || state === "connecting" || state === "disconnecting";
  var useLocation = tunnelOpen && (exitIp || !!location.hostname);

  return {
    ignored: false,
    state: state,
    active: state === "connected",
    locationCountry: useLocation ? String(location.country || "") : "",
    locationCity: useLocation ? String(location.city || "") : "",
    lockedDown: details.locked_down === true,
    mullvadExitIp: exitIp
  };
}

function parseAccountGet(raw, exitCode) {
  if (exitCode !== 0) {
    return { loggedIn: false, accountExpiry: "", deviceName: "", error: String(raw || "").trim() };
  }
  var text = String(raw || "");
  var expiryLine = text.match(/Expires at:\s+(\d{4}-\d{2}-\d{2})/);
  var deviceLine = text.match(/Device name:\s+(.+)$/m);
  var accountLine = text.match(/Mullvad account:\s+(\d+)/);
  if (!accountLine) {
    return { loggedIn: false, accountExpiry: "", deviceName: "", error: text.trim() };
  }
  return {
    loggedIn: true,
    accountExpiry: expiryLine ? expiryLine[1] : "",
    deviceName: deviceLine ? deviceLine[1].trim() : "",
    error: ""
  };
}

function parseLockdownGet(raw) {
  return /:\s*on\s*$/im.test(String(raw || ""));
}

function parseRelayGet(raw) {
  var text = String(raw || "");
  var country = "";
  var city = "";
  var countryMatch = text.match(/\bcountry\s+([a-z]{2})\b/i);
  var cityMatch = text.match(/\bcity\s+([a-z]{3})\b/i);
  if (countryMatch) country = countryMatch[1].toLowerCase();
  if (cityMatch) city = cityMatch[1].toLowerCase();
  return { country: country, city: city };
}

function mergeRecentCities(recentKeys, cities) {
  var list = cities || [];
  var recents = recentKeys || [];
  var byKey = {};
  var i;
  for (i = 0; i < list.length; i++) {
    byKey[list[i].countryCode + " " + list[i].cityCode] = list[i];
  }
  var out = [];
  var seen = {};
  for (i = 0; i < recents.length && out.length < 5; i++) {
    var key = String(recents[i] || "");
    if (!byKey[key] || seen[key]) continue;
    out.push(byKey[key]);
    seen[key] = true;
  }
  for (i = 0; i < list.length; i++) {
    var k = list[i].countryCode + " " + list[i].cityCode;
    if (seen[k]) continue;
    out.push(list[i]);
  }
  return out;
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
