#include "omoide.h"

// A pattern is compiled the first time it is used and kept for the rest of the
// process. Commands run once and exit, so nothing is ever freed.
GRegex *re(const char *pattern, GRegexCompileFlags flags) {
  static GHashTable *cache = NULL;
  if (!cache)
    cache = g_hash_table_new(g_str_hash, g_str_equal);
  g_autofree char *key = g_strdup_printf("%u:%s", flags, pattern);
  GRegex *found = g_hash_table_lookup(cache, key);
  if (found)
    return found;

  g_autoptr(GError) error = NULL;
  GRegex *compiled = g_regex_new(pattern, flags | G_REGEX_OPTIMIZE, 0, &error);
  if (!compiled)
    die(1, "bad pattern %s: %s", pattern, error->message);   // a bug, not input
  g_hash_table_insert(cache, g_steal_pointer(&key), compiled);
  return compiled;
}

// `replacement` is literal: no \1 back-references, so text can never be read
// as a template.
char *re_replace(const char *pattern, const char *text, const char *replacement) {
  char *out = g_regex_replace_literal(re(pattern, 0), text, -1, 0, replacement, 0, NULL);
  return out ? out : g_strdup(text);
}
