(function (root, factory) {
  const search = factory();

  if (typeof module !== "undefined" && module.exports) module.exports = search;
  if (root) root.RailsWaybackSearch = search;
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  function normalizeQuery(value) {
    return String(value || "").trim().toLocaleLowerCase();
  }

  function searchableText(item, fields) {
    return fields.map(function (field) {
      return String(item[field] || "");
    }).join(" ").toLocaleLowerCase();
  }

  function preserveSelection(items, matches, selected, valueField) {
    const selectedValue = String(selected || "");
    if (!selectedValue || matches.some(function (item) {
      return String(item[valueField] || "") === selectedValue;
    })) return matches;

    const selectedItem = items.find(function (item) {
      return String(item[valueField] || "") === selectedValue;
    });
    if (!selectedItem) return matches;

    return items.filter(function (item) {
      return item === selectedItem || matches.indexOf(item) !== -1;
    });
  }

  function search(items, query, selected, fields, valueField) {
    const collection = Array.isArray(items) ? items : [];
    const normalized = normalizeQuery(query);
    const matches = normalized
      ? collection.filter(function (item) {
        return searchableText(item, fields).includes(normalized);
      })
      : collection.slice();

    return {
      matches: matches,
      visible: preserveSelection(collection, matches, selected, valueField)
    };
  }

  function searchReferences(references, query, selected) {
    return search(
      references,
      query,
      selected,
      ["full_name", "name", "label", "type"],
      "full_name"
    );
  }

  function searchCommits(commits, query, selected) {
    return search(
      commits,
      query,
      selected,
      ["sha", "short_sha", "subject", "author", "date"],
      "sha"
    );
  }

  return {
    normalizeQuery: normalizeQuery,
    searchReferences: searchReferences,
    searchCommits: searchCommits
  };
});
