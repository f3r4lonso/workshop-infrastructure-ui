// Client-side search, ported from Test-ResourceMatch / Test-WordMatch in src/loader.ps1.
// Pure functions only: no React, no DOM.

const COMBINING_MARKS = /\p{Mn}/gu;
const WHITESPACE = /\s+/u;
const REGEXP_SPECIALS = /[.*+?^${}()|[\]\\]/g;
const boundaryCache = new Map();

/** Lower-case and strip accents (NFD + remove non-spacing marks). */
export function normalizeText(text) {
  return String(text ?? '').normalize('NFD').replace(COMBINING_MARKS, '').toLowerCase();
}

function escapeRegExp(text) {
  return text.replace(REGEXP_SPECIALS, '\\$&');
}

/**
 * True when `word` occurs in `text`. Words of three characters or fewer must match a whole word
 * (not preceded or followed by a letter or digit), so "ui" does not match "build".
 */
export function wordMatches(text, word) {
  if (word.length <= 3) {
    let pattern = boundaryCache.get(word);
    if (!pattern) {
      pattern = new RegExp(`(?<![\\p{L}\\p{N}])${escapeRegExp(word)}(?![\\p{L}\\p{N}])`, 'u');
      boundaryCache.set(word, pattern);
    }
    return pattern.test(text);
  }
  return text.includes(word);
}

/** Splits a query into words; each word becomes [word, ...its synonyms]. */
export function parseQuery(query, synonyms = {}) {
  return normalizeText(query)
    .split(WHITESPACE)
    .filter(Boolean)
    .map((word) => {
      const alternatives = [word];
      const extra = synonyms && Object.hasOwn(synonyms, word) ? synonyms[word] : null;
      if (Array.isArray(extra)) {
        for (const alternative of extra) alternatives.push(normalizeText(alternative));
      }
      return alternatives;
    });
}

/** Every query word must match, through itself or one of its alternatives. */
export function matchesParsedQuery(searchText, parsedQuery) {
  const text = searchText ?? '';
  return parsedQuery.every((alternatives) => alternatives.some((word) => wordMatches(text, word)));
}

/** Items whose searchText matches the query; [] for an empty query. */
export function filterItems(items, query, synonyms) {
  const parsed = parseQuery(query, synonyms);
  if (parsed.length === 0) return [];
  return items.filter((item) => matchesParsedQuery(item.searchText, parsed));
}
