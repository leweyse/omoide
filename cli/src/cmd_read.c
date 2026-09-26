// The read APIs: what the bar, the library and the Space window ask for.
#include "omoide.h"

#include <string.h>

static json_object *cards_from(sqlite3 *db, sqlite3_stmt *rows) {
  json_object *cards = json_object_new_array();
  while (db_step(rows))
    json_object_array_add(cards, memory_card(db, rows));
  return cards;
}

// The card for `id` if it is a ready memory, else NULL.
static json_object *ready_card(sqlite3 *db, const char *id) {
  g_autoptr(sqlite3_stmt) memory = db_query(
    db, "SELECT * FROM memories WHERE id = ? AND status = 'ready'", "s", id);
  return db_step(memory) ? memory_card(db, memory) : NULL;
}

// Match any term, as a prefix. Without FTS5's `*` a search typed one character
// at a time finds nothing until the final letter of a word -- "bandcam" would
// miss "bandcamp". Terms are split on non-word characters, so none can carry
// a quote into the query.
static char *fts_escape(const char *query) {
  g_auto(GStrv) terms = g_regex_split(re("\\W+", 0), query ? query : "", 0);
  g_autoptr(GString) match = g_string_new(NULL);
  for (size_t i = 0; terms[i]; i++) {
    if (!*terms[i])
      continue;
    if (match->len)
      g_string_append(match, " OR ");
    g_string_append_printf(match, "\"%s\"*", terms[i]);
  }
  return g_string_free(g_steal_pointer(&match), FALSE);
}

int cmd_state(int argc, char **argv) {
  parse_options("state", NULL, 0, &argc, &argv);
  sqlite3 *db = db_open(false);
  g_autoptr(sqlite3_stmt) counts = db_query(
    db, "SELECT COUNT(*) AS memories, SUM(ai_status = 'pending') AS pending, "
        "SUM(ai_status = 'failed') AS failed FROM memories WHERE status = 'ready'", NULL);
  db_step(counts);
  g_autoptr(sqlite3_stmt) pending = db_query(db, "SELECT COUNT(*) AS n " LIVE_REMINDER, NULL);
  db_step(pending);
  g_autoptr(sqlite3_stmt) upcoming = db_query(
    db, "SELECT i.title, r.fire_at " LIVE_REMINDER " ORDER BY r.fire_at LIMIT 1", NULL);

  json_object *next = NULL;
  if (db_step(upcoming)) {
    next = json_object_new_object();
    json_object_object_add(next, "title", json_str(col_str(upcoming, "title")));
    json_object_object_add(next, "fireAt", json_str(col_str(upcoming, "fire_at")));
  }
  g_autoptr(json_object) ai = ai_settings();
  g_auto(GStrv) provider = resolve_provider(ai);

  json_object *out = json_object_new_object();
  json_object_object_add(out, "memories", json_object_new_int64(col_int(counts, "memories")));
  json_object_object_add(out, "enriching", json_object_new_int64(col_int(counts, "pending")));
  json_object_object_add(out, "failed", json_object_new_int64(col_int(counts, "failed")));
  json_object_object_add(out, "pendingReminders", json_object_new_int64(col_int(pending, "n")));
  json_object_object_add(out, "next", next);
  json_object_object_add(out, "aiConfigured", json_object_new_boolean(provider != NULL));
  json_object_object_add(out, "voiceAvailable", json_object_new_boolean(has("voxtype")));
  emit(out);
  return 0;
}

int cmd_list(int argc, char **argv) {
  int limit = 50;
  g_autofree char *collection = NULL;
  const GOptionEntry entries[] = {
    { "limit", 0, 0, G_OPTION_ARG_INT, &limit, "at most this many", "N" },
    { "collection", 0, 0, G_OPTION_ARG_STRING, &collection, "only this collection", "NAME" },
    G_OPTION_ENTRY_NULL
  };
  parse_options("list", entries, 0, &argc, &argv);
  sqlite3 *db = db_open(false);

  g_autoptr(sqlite3_stmt) rows = collection
    ? db_query(db, "SELECT * FROM memories WHERE status = 'ready' AND id IN "
                   "(SELECT mc.memory_id FROM memory_collections mc "
                   "JOIN collections c ON c.id = mc.collection_id WHERE c.name = ?) "
                   "ORDER BY created_at DESC LIMIT ?", "si", collection, (int64_t)limit)
    : db_query(db, "SELECT * FROM memories WHERE status = 'ready' "
                   "ORDER BY created_at DESC LIMIT ?", "i", (int64_t)limit);
  json_object *out = json_object_new_object();
  json_object_object_add(out, "memories", cards_from(db, rows));
  emit(out);
  return 0;
}

static json_object *reminders_of(sqlite3 *db, const char *item_id) {
  json_object *list = json_object_new_array();
  g_autoptr(sqlite3_stmt) rows = db_query(
    db, "SELECT * FROM reminders WHERE item_id = ?", "s", item_id);
  while (db_step(rows)) {
    json_object *r = json_object_new_object();
    json_object_object_add(r, "id", json_str(col_str(rows, "id")));
    json_object_object_add(r, "fireAt", json_str(col_str(rows, "fire_at")));
    json_object_object_add(r, "offsetMin", col_null(rows, "trigger_offset_min") ? NULL
                           : json_object_new_int64(col_int(rows, "trigger_offset_min")));
    json_object_object_add(r, "status", json_str(col_str(rows, "status")));
    json_object_array_add(list, r);
  }
  return list;
}

// An image block's payload names its attachment; the page needs the files.
static void resolve_image(sqlite3 *db, json_object *payload) {
  g_autoptr(sqlite3_stmt) attachment = db_query(
    db, "SELECT * FROM attachments WHERE id = ?", "s", json_get_str(payload, "attachment_id"));
  if (!db_step(attachment))
    return;
  g_autofree char *path = g_build_filename(paths()->data_dir, col_str(attachment, "rel_path"), NULL);
  const char *thumb = col_str(attachment, "thumb_path");
  g_autofree char *thumb_path = thumb && *thumb
    ? g_build_filename(paths()->data_dir, thumb, NULL) : g_strdup(path);
  json_object_object_add(payload, "path", json_object_new_string(path));
  json_object_object_add(payload, "thumb", json_object_new_string(thumb_path));
  json_object_object_add(payload, "aspect", aspect_of(attachment));
}

int cmd_show(int argc, char **argv) {
  g_autofree char *id = NULL;
  const GOptionEntry entries[] = {
    { "id", 0, 0, G_OPTION_ARG_STRING, &id, "the memory", "ID" },
    G_OPTION_ENTRY_NULL
  };
  parse_options("show", entries, 0, &argc, &argv);
  require_option("show", "--id", id);
  sqlite3 *db = db_open(false);

  g_autoptr(sqlite3_stmt) memory = db_query(db, "SELECT * FROM memories WHERE id = ?", "s", id);
  if (!db_step(memory))
    die(1, "no such memory: %s", id);

  json_object *blocks = json_object_new_array();
  g_autoptr(sqlite3_stmt) block_rows = db_query(
    db, "SELECT * FROM blocks WHERE memory_id = ? ORDER BY position", "s", id);
  while (db_step(block_rows)) {
    json_object *payload = json_tokener_parse(col_str(block_rows, "payload"));
    if (!payload)
      payload = json_object_new_object();
    if (g_strcmp0(col_str(block_rows, "type"), "image") == 0
        && json_object_is_type(payload, json_type_object))
      resolve_image(db, payload);
    json_object *block = json_object_new_object();
    json_object_object_add(block, "id", json_str(col_str(block_rows, "id")));
    json_object_object_add(block, "type", json_str(col_str(block_rows, "type")));
    json_object_object_add(block, "payload", payload);
    json_object_object_add(block, "origin", json_str(col_str(block_rows, "origin")));
    json_object_object_add(block, "edited", json_object_new_boolean(col_int(block_rows, "edited") != 0));
    json_object_array_add(blocks, block);
  }

  // Cancelled items are gone as far as the page is concerned: returning them
  // kept a deleted to-do rendering, which looked exactly like a failed delete.
  json_object *items = json_object_new_array();
  g_autoptr(sqlite3_stmt) item_rows = db_query(
    db, "SELECT * FROM items WHERE memory_id = ? AND status != 'cancelled' "
        "ORDER BY created_at", "s", id);
  while (db_step(item_rows)) {
    json_object *item = json_object_new_object();
    json_object_object_add(item, "id", json_str(col_str(item_rows, "id")));
    json_object_object_add(item, "kind", json_str(col_str(item_rows, "kind")));
    json_object_object_add(item, "title", json_str(col_str(item_rows, "title")));
    json_object_object_add(item, "dueAt", json_str(col_str(item_rows, "due_at")));
    json_object_object_add(item, "startsAt", json_str(col_str(item_rows, "starts_at")));
    json_object_object_add(item, "endsAt", json_str(col_str(item_rows, "ends_at")));
    json_object_object_add(item, "allDay", json_object_new_boolean(col_int(item_rows, "all_day") != 0));
    json_object_object_add(item, "location", json_str_or_empty(col_str(item_rows, "location")));
    json_object_object_add(item, "mapUrl", json_str_or_empty(col_str(item_rows, "map_url")));
    json_object_object_add(item, "status", json_str(col_str(item_rows, "status")));
    json_object_object_add(item, "completedAt", json_str(col_str(item_rows, "completed_at")));
    json_object_object_add(item, "reminders", reminders_of(db, col_str(item_rows, "id")));
    json_object_array_add(items, item);
  }

  json_object *tags = json_object_new_array();
  g_autoptr(sqlite3_stmt) tag_rows = db_query(db, "SELECT tag FROM tags WHERE memory_id = ?", "s", id);
  while (db_step(tag_rows))
    json_object_array_add(tags, json_str(col_str(tag_rows, "tag")));

  json_object *collections = json_object_new_array();
  g_autoptr(sqlite3_stmt) collection_rows = db_query(
    db, "SELECT c.id, c.name FROM collections c JOIN memory_collections mc "
        "ON mc.collection_id = c.id WHERE mc.memory_id = ?", "s", id);
  while (db_step(collection_rows)) {
    json_object *c = json_object_new_object();
    json_object_object_add(c, "id", json_str(col_str(collection_rows, "id")));
    json_object_object_add(c, "name", json_str(col_str(collection_rows, "name")));
    json_object_array_add(collections, c);
  }

  json_object *out = json_object_new_object();
  json_object_object_add(out, "id", json_str(col_str(memory, "id")));
  json_object_object_add(out, "title", json_str_or_empty(col_str(memory, "title")));
  json_object_object_add(out, "lede", json_str_or_empty(col_str(memory, "lede")));
  json_object_object_add(out, "createdAt", json_str(col_str(memory, "created_at")));
  json_object_object_add(out, "aiStatus", json_str(col_str(memory, "ai_status")));
  json_object_object_add(out, "aiError", json_str_or_empty(col_str(memory, "ai_error")));
  json_object_object_add(out, "blocks", blocks);
  json_object_object_add(out, "items", items);
  json_object_object_add(out, "tags", tags);
  json_object_object_add(out, "collections", collections);
  emit(out);
  return 0;
}

int cmd_search(int argc, char **argv) {
  g_autofree char *q = NULL;
  int limit = 50;
  const GOptionEntry entries[] = {
    { "q", 0, 0, G_OPTION_ARG_STRING, &q, "what to look for", "TEXT" },
    { "limit", 0, 0, G_OPTION_ARG_INT, &limit, "at most this many", "N" },
    G_OPTION_ENTRY_NULL
  };
  parse_options("search", entries, 0, &argc, &argv);
  require_option("search", "--q", q);
  sqlite3 *db = db_open(false);

  json_object *results = json_object_new_array();
  g_autofree char *match = fts_escape(q);
  if (*match) {
    g_autoptr(sqlite3_stmt) rows = db_query(
      db, "SELECT memory_id FROM memories_fts WHERE memories_fts MATCH ? "
          "ORDER BY rank LIMIT ?", "si", match, (int64_t)limit);
    while (db_step(rows)) {
      json_object *card = ready_card(db, col_str(rows, "memory_id"));
      if (card)
        json_object_array_add(results, card);
    }
  }
  json_object *out = json_object_new_object();
  json_object_object_add(out, "results", results);
  emit(out);
  return 0;
}

// The To-do archive: one query, grouped by time and completion. Grouping never
// consults a reminder's state -- a fired alarm says nothing about whether the
// to-do is done, so it stays in Past until checked off.
int cmd_archive(int argc, char **argv) {
  parse_options("archive", NULL, 0, &argc, &argv);
  sqlite3 *db = db_open(false);
  g_autoptr(GDateTime) current = now_utc();

  // No separate "anytime" group: an undated to-do is still something ahead.
  json_object *suggested = json_object_new_array();
  json_object *upcoming = json_object_new_array();
  json_object *past = json_object_new_array();
  json_object *completed = json_object_new_array();

  // Newest first, not by due date: this page is the full list, and For you is
  // where what matters today gets picked out.
  g_autoptr(sqlite3_stmt) rows = db_query(
    db, "SELECT * FROM items WHERE kind = 'todo' AND status IN ('active', 'suggested') "
        "ORDER BY created_at DESC", NULL);
  while (db_step(rows)) {
    json_object *entry = json_object_new_object();
    json_object_object_add(entry, "id", json_str(col_str(rows, "id")));
    json_object_object_add(entry, "memoryId", json_str(col_str(rows, "memory_id")));
    json_object_object_add(entry, "title", json_str(col_str(rows, "title")));
    json_object_object_add(entry, "dueAt", json_str(col_str(rows, "due_at")));
    json_object_object_add(entry, "completedAt", json_str(col_str(rows, "completed_at")));
    json_object_object_add(entry, "status", json_str(col_str(rows, "status")));
    json_object_object_add(entry, "createdAt", json_str(col_str(rows, "created_at")));

    g_autoptr(GDateTime) due = parse_iso(col_str(rows, "due_at"));
    const char *completed_at = col_str(rows, "completed_at");
    if (g_strcmp0(col_str(rows, "status"), "suggested") == 0)
      json_object_array_add(suggested, entry);
    else if (completed_at && *completed_at)
      json_object_array_add(completed, entry);
    else if (!due || g_date_time_compare(due, current) >= 0)
      json_object_array_add(upcoming, entry);
    else
      json_object_array_add(past, entry);
  }

  json_object *out = json_object_new_object();
  json_object_object_add(out, "suggested", suggested);
  json_object_object_add(out, "upcoming", upcoming);
  json_object_object_add(out, "past", past);
  json_object_object_add(out, "completed", completed);
  emit(out);
  return 0;
}

// Only what the user linked. Nothing is inferred.
int cmd_related(int argc, char **argv) {
  g_autofree char *id = NULL;
  const GOptionEntry entries[] = {
    { "id", 0, 0, G_OPTION_ARG_STRING, &id, "the memory", "ID" },
    G_OPTION_ENTRY_NULL
  };
  parse_options("related", entries, 0, &argc, &argv);
  require_option("related", "--id", id);
  sqlite3 *db = db_open(false);

  json_object *linked = json_object_new_array();
  g_autoptr(sqlite3_stmt) rows = db_query(
    db, "SELECT * FROM links WHERE (from_id = ? OR to_id = ?) ORDER BY created_at DESC",
    "ss", id, id);
  while (db_step(rows)) {
    const char *from = col_str(rows, "from_id");
    const char *other = g_strcmp0(from, id) == 0 ? col_str(rows, "to_id") : from;
    json_object *card = ready_card(db, other);
    if (card)
      json_object_array_add(linked, card);
  }
  json_object *out = json_object_new_object();
  json_object_object_add(out, "linked", linked);
  emit(out);
  return 0;
}

// Memories available to link by hand. Everything the user has already ruled
// on is excluded, so the list only ever offers what would be a new link.
int cmd_candidates(int argc, char **argv) {
  g_autofree char *id = NULL;
  g_autofree char *q = NULL;
  int limit = 40;
  const GOptionEntry entries[] = {
    { "id", 0, 0, G_OPTION_ARG_STRING, &id, "the memory", "ID" },
    { "q", 0, 0, G_OPTION_ARG_STRING, &q, "narrow by text", "TEXT" },
    { "limit", 0, 0, G_OPTION_ARG_INT, &limit, "at most this many", "N" },
    G_OPTION_ENTRY_NULL
  };
  parse_options("candidates", entries, 0, &argc, &argv);
  require_option("candidates", "--id", id);
  sqlite3 *db = db_open(false);

  g_autoptr(GHashTable) skip = g_hash_table_new_full(g_str_hash, g_str_equal, g_free, NULL);
  g_hash_table_add(skip, g_strdup(id));
  {
    g_autoptr(sqlite3_stmt) links = db_query(
      db, "SELECT from_id, to_id FROM links WHERE from_id = ? OR to_id = ?", "ss", id, id);
    while (db_step(links)) {
      const char *from = col_str(links, "from_id");
      g_hash_table_add(skip, g_strdup(g_strcmp0(from, id) == 0 ? col_str(links, "to_id") : from));
    }
  }

  g_autoptr(sqlite3_stmt) rows = NULL;
  g_autofree char *match = q && *q ? fts_escape(q) : NULL;
  if (q && *q) {
    // FTS5 wants the table name in MATCH, not an alias.
    if (*match)
      rows = db_query(db, "SELECT m.* FROM memories_fts JOIN memories m "
                          "ON m.id = memories_fts.memory_id "
                          "WHERE memories_fts MATCH ? AND m.status = 'ready' "
                          "ORDER BY rank LIMIT 100", "s", match);
  } else {
    rows = db_query(db, "SELECT * FROM memories WHERE status = 'ready' "
                        "ORDER BY created_at DESC LIMIT 100", NULL);
  }

  json_object *found = json_object_new_array();
  while (rows && db_step(rows))
    if (!g_hash_table_contains(skip, col_str(rows, "id")))
      json_object_array_add(found, memory_card(db, rows));

  // A slice, as out[:limit] was: a negative limit drops that many from the end.
  const int total = (int)json_object_array_length(found);
  const int keep = limit >= 0 ? MIN(limit, total) : MAX(0, total + limit);
  json_object *candidates = json_object_new_array();
  for (int i = 0; i < keep; i++)
    json_object_array_add(candidates, json_object_get(json_object_array_get_idx(found, i)));
  json_object_put(found);

  json_object *out = json_object_new_object();
  json_object_object_add(out, "candidates", candidates);
  emit(out);
  return 0;
}
