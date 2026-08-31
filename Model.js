.pragma library

// Pure helpers for the Game Library panel. Kept free of QML types so they can
// be reasoned about (and unit-tested) without a running shell.

function parseIndex(raw) {
  var text = String(raw || "").trim()
  if (text === "") return { ok: false, error: "Indexer returned nothing" }
  try {
    var parsed = JSON.parse(text)
    if (!parsed || typeof parsed !== "object") return { ok: false, error: "Malformed index" }
    return parsed
  } catch (e) {
    return { ok: false, error: "Could not parse index: " + e }
  }
}

function steamGames(index) {
  var steam = index && index.steam ? index.steam : null
  return steam && steam.games instanceof Array ? steam.games : []
}

function webGames(index) {
  var web = index && index.web ? index.web : null
  return web && web.games instanceof Array ? web.games : []
}

// A stable, unique key per entry — Steam appids and web ids never collide
// because they carry different prefixes.
function entryKey(entry) {
  if (!entry) return ""
  return entry.kind === "steam" ? "steam:" + entry.appid : "web:" + entry.id
}

function playtimeText(minutes) {
  var value = Number(minutes || 0)
  if (value <= 0) return ""
  if (value < 60) return value + "m"
  var hours = value / 60
  return (hours < 10 ? hours.toFixed(1) : Math.round(hours)) + "h"
}

function sizeText(bytes) {
  var value = Number(bytes || 0)
  if (value <= 0) return ""
  var units = ["B", "KB", "MB", "GB", "TB"]
  var i = 0
  while (value >= 1024 && i < units.length - 1) {
    value /= 1024
    i++
  }
  return (value < 10 && i > 1 ? value.toFixed(1) : Math.round(value)) + " " + units[i]
}

function lastPlayedText(epochSeconds) {
  var stamp = Number(epochSeconds || 0)
  if (stamp <= 0) return ""
  var days = Math.floor((Date.now() / 1000 - stamp) / 86400)
  if (days <= 0) return "today"
  if (days === 1) return "yesterday"
  if (days < 30) return days + "d ago"
  if (days < 365) return Math.round(days / 30) + "mo ago"
  var years = days / 365
  return (years < 2 ? "1y ago" : Math.round(years) + "y ago")
}

// The right-hand subtitle for a row: the most useful fact we have, not all of
// them. Installed games lead with size, played games with playtime.
function subtitle(entry) {
  if (!entry) return ""
  if (entry.kind === "web") {
    var bits = []
    if (entry.category) bits.push(entry.category)
    if (entry.author) bits.push("by " + entry.author)
    if (bits.length === 0 && entry.description) return entry.description
    return bits.join(" · ")
  }
  var parts = []
  var played = playtimeText(entry.playtimeMin)
  if (played) parts.push(played + " played")
  var last = lastPlayedText(entry.lastPlayed)
  if (last) parts.push(last)
  if (entry.installed) {
    var size = sizeText(entry.sizeBytes)
    if (size) parts.push(size)
  } else {
    parts.push("not installed")
  }
  return parts.join(" · ")
}

function coverSource(entry, showCovers) {
  if (!entry || !showCovers) return ""
  if (entry.kind === "web") return entry.thumb || ""
  if (entry.cover) return "file://" + entry.cover
  return entry.coverUrl || ""
}

// Nerd Font glyph used when there is no artwork to show.
function glyph(entry) {
  if (!entry) return ""
  if (entry.kind === "steam") return ""
  if (entry.icon) return entry.icon
  if (entry.source === "itch") return ""
  return "󰄌"
}

// Subsequence match with the forgiving behaviour of a fuzzy file finder:
// "agemp" finds "Age of Empires". Returns a score, or -1 for no match.
//
// The span limit is what keeps it useful. Without it, a five-letter query
// matches almost any long title by scattering its letters across the whole
// string -- "chess" happily matches "Penny Ar[c]ade Adventures: On t[h]e ..."
// and buries the real result. Requiring the matched characters to sit close
// together throws those away while still allowing real acronyms and typos.
function matchScore(name, query) {
  if (!query) return 0
  var haystack = String(name || "").toLowerCase()
  var needle = String(query).toLowerCase().replace(/\s+/g, "")
  if (needle === "") return 0

  var direct = haystack.indexOf(needle)
  if (direct === 0) return 1000
  if (direct > 0) return 900 - Math.min(direct, 400)

  var hi = 0
  var streak = 0
  var score = 0
  var first = -1
  var last = -1
  for (var ni = 0; ni < needle.length; ni++) {
    var ch = needle[ni]
    var found = -1
    while (hi < haystack.length) {
      if (haystack[hi] === ch) { found = hi; hi++; break }
      hi++
    }
    if (found === -1) return -1
    if (first === -1) first = found
    last = found
    // Reward matches that start a word and runs of consecutive characters.
    if (found === 0 || " :-_.,".indexOf(haystack[found - 1]) !== -1) score += 12
    streak = (ni > 0 && found > 0 && haystack[found - 1] === needle[ni - 1]) ? streak + 1 : 0
    score += 4 + streak * 3
  }

  // Matched characters must be reasonably clustered, or this is noise.
  if (last - first > needle.length * 2 + 2) return -1
  return score
}

function filterEntries(entries, query) {
  if (!query) return entries.slice()
  var scored = []
  for (var i = 0; i < entries.length; i++) {
    var entry = entries[i]
    var best = matchScore(entry.name, query)
    // Web entries also match on their category, so "cloud" finds GeForce NOW.
    if (entry.kind === "web" && entry.category) {
      best = Math.max(best, matchScore(entry.category, query) - 50)
    }
    if (best >= 0) scored.push({ entry: entry, score: best, order: i })
  }
  scored.sort(function (a, b) {
    return b.score - a.score || a.order - b.order
  })
  return scored.map(function (s) { return s.entry })
}

// Build the flat row list the panel renders, with section headers inlined so
// keyboard navigation only has to walk one array.
function buildRows(index, options) {
  var query = options.query || ""
  var rows = []
  var steam = filterEntries(steamGames(index), query)
  var web = options.showWeb ? filterEntries(webGames(index), query) : []

  if (!query && options.recentCount > 0) {
    var recent = steam.filter(function (g) { return g.lastPlayed > 0 }).slice(0, options.recentCount)
    if (recent.length > 0) {
      rows.push({ header: "RECENTLY PLAYED" })
      for (var r = 0; r < recent.length; r++) rows.push({ entry: recent[r] })
    }
  }

  if (steam.length > 0) {
    // The indexer sorts by recency, which is what the pinned section wants.
    // The full library is for browsing, so alphabetical -- otherwise it just
    // repeats the rows immediately above it.
    var library = query ? steam : steam.slice().sort(function (a, b) {
      return a.name.localeCompare(b.name, undefined, { numeric: true, sensitivity: "base" })
    })
    rows.push({ header: query ? "STEAM" : "STEAM LIBRARY", count: library.length })
    for (var s = 0; s < library.length; s++) rows.push({ entry: library[s] })
  }

  if (web.length > 0) {
    rows.push({ header: "WEB GAMES", count: web.length })
    for (var w = 0; w < web.length; w++) rows.push({ entry: web[w] })
  }


  return rows
}

function firstSelectableIndex(rows) {
  for (var i = 0; i < rows.length; i++) if (rows[i].entry) return i
  return -1
}

function nextSelectableIndex(rows, from, step) {
  var i = from + step
  while (i >= 0 && i < rows.length) {
    if (rows[i].entry) return i
    i += step
  }
  return from
}
