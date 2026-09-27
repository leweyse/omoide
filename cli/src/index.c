#include "omoide.h"

#include <string.h>

// A path the database stores relative to the data dir, made absolute.
char *data_path(const char *relative) {
  if (relative[0] == '/')
    return g_strdup(relative);
  return g_build_filename(paths()->data_dir, relative, NULL);
}

static json_object *string_column_list(sqlite3 *db, const char *sql, const char *id) {
  json_object *list = json_object_new_array();
  g_autoptr(sqlite3_stmt) rows = db_query(db, sql, "s", id);
  while (db_step(rows))
    json_object_array_add(list, json_str_or_empty((const char *)sqlite3_column_text(rows, 0)));
  return list;
}

// The domain of a memory's source block, if it has one.
static char *source_domain(sqlite3 *db, const char *memory_id) {
  g_autoptr(sqlite3_stmt) row = db_query(
      db, "SELECT payload FROM blocks WHERE memory_id = ? AND type = 'source' LIMIT 1", "s", memory_id);
  if (!db_step(row))
    return NULL;
  g_autoptr(json_object) payload = json_tokener_parse(col_str(row, "payload"));
  const char *domain = json_get_str(payload, "domain");
  return domain && *domain ? g_strdup(domain) : NULL;
}

// What the capture is, from what it actually holds.
static const char *memory_kind(sqlite3 *db, const char *memory_id) {
  bool image = false;
  g_autoptr(sqlite3_stmt) rows =
      db_query(db, "SELECT kind FROM attachments WHERE memory_id = ?", "s", memory_id);
  while (db_step(rows)) {
    const char *kind = col_str(rows, "kind");
    if (g_strcmp0(kind, "audio") == 0)
      return "voice";
    image = image || g_strcmp0(kind, "image") == 0;
  }
  return image ? "screenshot" : "note";
}

// Width over height, or 0 when the attachment was never measured. 0 means
// unknown, and every caller falls back rather than dividing by it.
json_object *aspect_of(sqlite3_stmt *attachment) {
  if (!attachment)
    return json_round4(0);
  const int64_t width = col_int(attachment, "width");
  const int64_t height = col_int(attachment, "height");
  if (!width || !height)
    return json_round4(0);
  return json_round4((double)width / (double)height);
}

json_object *memory_card(sqlite3 *db, sqlite3_stmt *memory) {
  const char *id = col_str(memory, "id");
  json_object *card = json_object_new_object();

  g_autoptr(sqlite3_stmt) thumb = db_query(db,
      "SELECT thumb_path, rel_path, width, height FROM attachments "
      "WHERE memory_id = ? AND kind = 'image' ORDER BY rowid LIMIT 1",
      "s", id);
  const bool has_thumb = db_step(thumb);

  g_autoptr(sqlite3_stmt) todos = db_query(db,
      "SELECT COUNT(*) AS n FROM items WHERE memory_id = ? AND kind = 'todo' "
      "AND status = 'active' AND completed_at IS NULL",
      "s", id);
  db_step(todos);

  g_autofree char *domain = source_domain(db, id);
  json_object_object_add(card, "id", json_str(id));
  json_object_object_add(card, "title", json_str_or_empty(col_str(memory, "title")));
  json_object_object_add(card, "lede", json_str_or_empty(col_str(memory, "lede")));
  json_object_object_add(card, "createdAt", json_str(col_str(memory, "created_at")));
  json_object_object_add(card, "aiStatus", json_str(col_str(memory, "ai_status")));
  json_object_object_add(card, "kind", json_object_new_string(memory_kind(db, id)));
  json_object_object_add(card, "collections",
      string_column_list(db,
          "SELECT c.name FROM collections c JOIN memory_collections mc "
          "ON mc.collection_id = c.id WHERE mc.memory_id = ? ORDER BY c.name",
          id));
  json_object_object_add(card, "domain", json_str_or_empty(domain));
  json_object_object_add(
      card, "tags", string_column_list(db, "SELECT tag FROM tags WHERE memory_id = ? ORDER BY tag", id));
  json_object_object_add(card, "openTodos", json_object_new_int64(col_int(todos, "n")));

  g_autofree char *thumb_path = NULL;
  if (has_thumb && col_str(thumb, "thumb_path") && *col_str(thumb, "thumb_path"))
    thumb_path = data_path(col_str(thumb, "thumb_path"));
  else if (has_thumb)
    thumb_path = data_path(col_str(thumb, "rel_path"));
  json_object_object_add(card, "thumb", json_str_or_empty(thumb_path));
  json_object_object_add(card, "aspect", aspect_of(has_thumb ? thumb : NULL));
  return card;
}

// --- facets

// How a domain is shown on a chip. Anything not listed falls back to its
// registrable name, so a new site needs no code.
static const struct {
  const char *domain, *label;
} DOMAIN_LABELS[] = {
  { "x.com", "X" },
  { "twitter.com", "X" },
  { "github.com", "GitHub" },
  { "youtube.com", "YouTube" },
  { "youtu.be", "YouTube" },
  { "instagram.com", "Instagram" },
  { "reddit.com", "Reddit" },
  { "news.ycombinator.com", "Hacker News" },
  { "lu.ma", "Luma" },
};

// First character upper, the rest lower, as Python's str.capitalize().
static char *capitalize(const char *text) {
  if (!*text)
    return g_strdup("");
  const gunichar first = g_unichar_totitle(g_utf8_get_char(text));
  char head[8] = { 0 };
  g_unichar_to_utf8(first, head);
  g_autofree char *rest = g_utf8_strdown(g_utf8_next_char(text), -1);
  return g_strconcat(head, rest, NULL);
}

static char *domain_label(const char *domain) {
  for (size_t i = 0; i < G_N_ELEMENTS(DOMAIN_LABELS); i++)
    if (g_str_equal(domain, DOMAIN_LABELS[i].domain))
      return g_strdup(DOMAIN_LABELS[i].label);
  g_auto(GStrv) parts = g_strsplit(domain, ".", -1);
  const char *last = NULL;
  for (size_t i = 0; parts[i]; i++) {
    const char *p = parts[i];
    if (strcmp(p, "www") && strcmp(p, "com") && strcmp(p, "org") && strcmp(p, "net") && strcmp(p, "io"))
      last = p;
  }
  return last ? capitalize(last) : g_strdup(domain);
}

typedef struct {
  char *id, *label, *group;
  int count;
  int order;   // first-seen, the tie-break Python's stable sort gave
} Facet;

static void facet_free(gpointer data) {
  Facet *f = data;
  g_free(f->id);
  g_free(f->label);
  g_free(f->group);
  g_free(f);
}

static void bump(GPtrArray *facets, GHashTable *by_id, const char *id, const char *label, const char *group) {
  Facet *f = g_hash_table_lookup(by_id, id);
  if (!f) {
    f = g_new0(Facet, 1);
    f->id = g_strdup(id);
    f->label = g_strdup(label);
    f->group = g_strdup(group);
    f->order = (int)facets->len;
    g_ptr_array_add(facets, f);
    g_hash_table_insert(by_id, f->id, f);
  }
  f->count++;
}

static int group_rank(const char *group) {
  return g_str_equal(group, "kind") ? 0 : g_str_equal(group, "source") ? 1 : 2;
}

// Kinds first, then sources, then tags; by count within each group.
static int facet_compare(gconstpointer a, gconstpointer b) {
  const Facet *x = *(Facet *const *)a, *y = *(Facet *const *)b;
  if (group_rank(x->group) != group_rank(y->group))
    return group_rank(x->group) - group_rank(y->group);
  if (x->count != y->count)
    return y->count - x->count;
  g_autofree char *lx = g_utf8_strdown(x->label, -1);
  g_autofree char *ly = g_utf8_strdown(y->label, -1);
  const int by_label = strcmp(lx, ly);
  return by_label ? by_label : x->order - y->order;
}

// Filter chips, counted: what the capture is, where it came from, and what the
// model tagged it. Facets with a single member are dropped: a chip that
// narrows six memories down to one is a worse way to find it than scrolling.
static json_object *build_facets(json_object *cards) {
  g_autoptr(GPtrArray) facets = g_ptr_array_new_with_free_func(facet_free);
  g_autoptr(GHashTable) by_id = g_hash_table_new(g_str_hash, g_str_equal);

  for (size_t i = 0; i < json_object_array_length(cards); i++) {
    json_object *card = json_object_array_get_idx(cards, i);
    const char *kind = json_get_str(card, "kind");
    if (!kind || !*kind)
      kind = "note";
    g_autofree char *kind_id = g_strconcat("kind:", kind, NULL);
    g_autofree char *kind_label = g_str_equal(kind, "screenshot") ? g_strdup("Screenshot")
        : g_str_equal(kind, "note")                               ? g_strdup("Note")
        : g_str_equal(kind, "voice")                              ? g_strdup("Voice")
                                                                  : capitalize(kind);
    bump(facets, by_id, kind_id, kind_label, "kind");

    const char *domain = json_get_str(card, "domain");
    if (domain && *domain) {
      g_autofree char *source_id = g_strconcat("source:", domain, NULL);
      g_autofree char *label = domain_label(domain);
      bump(facets, by_id, source_id, label, "source");
    }

    json_object *tags = json_get(card, "tags");
    for (size_t t = 0; t < json_object_array_length(tags) && t < 4; t++) {
      const char *tag = json_object_get_string(json_object_array_get_idx(tags, t));
      g_autofree char *tag_id = g_strconcat("tag:", tag, NULL);
      bump(facets, by_id, tag_id, tag, "tag");
    }
  }

  g_ptr_array_sort(facets, facet_compare);
  json_object *out = json_object_new_array();
  for (size_t i = 0; i < facets->len && json_object_array_length(out) < 24; i++) {
    const Facet *f = g_ptr_array_index(facets, i);
    if (f->count <= 1)
      continue;
    json_object *entry = json_object_new_object();
    json_object_object_add(entry, "id", json_object_new_string(f->id));
    json_object_object_add(entry, "label", json_object_new_string(f->label));
    json_object_object_add(entry, "group", json_object_new_string(f->group));
    json_object_object_add(entry, "count", json_object_new_int(f->count));
    json_object_array_add(out, entry);
  }
  return out;
}

// --- search index

static void append_part(GString *out, const char *part) {
  if (!part || !*part)
    return;
  if (out->len)
    g_string_append_c(out, ' ');
  g_string_append(out, part);
}

static char *block_text(const char *payload_text) {
  g_autoptr(json_object) payload = json_tokener_parse(payload_text ? payload_text : "");
  GString *out = g_string_new(NULL);
  if (!payload || !json_object_is_type(payload, json_type_object))
    return g_string_free(out, FALSE);
  append_part(out, json_get_str(payload, "text"));
  append_part(out, json_get_str(payload, "heading"));
  append_part(out, json_get_str(payload, "title"));
  append_part(out, json_get_str(payload, "url"));
  json_object *items = json_get(payload, "items");
  for (size_t i = 0; json_object_is_type(items, json_type_array) && i < json_object_array_length(items);
      i++) {
    json_object *entry = json_object_array_get_idx(items, i);
    append_part(out, json_get_str(entry, "label"));
    append_part(out, json_get_str(entry, "text"));
  }
  return g_string_free(out, FALSE);
}

void refresh_fts(sqlite3 *db, const char *memory_id) {
  db_exec(db, "BEGIN");
  g_autoptr(sqlite3_stmt) targets = NULL;
  if (memory_id) {
    g_autoptr(sqlite3_stmt) clear =
        db_query(db, "DELETE FROM memories_fts WHERE memory_id = ?", "s", memory_id);
    db_step(clear);
    targets = db_query(db, "SELECT * FROM memories WHERE id = ?", "s", memory_id);
  } else {
    db_exec(db, "DELETE FROM memories_fts");
    targets = db_query(db, "SELECT * FROM memories", NULL);
  }

  while (db_step(targets)) {
    const char *id = col_str(targets, "id");
    g_autoptr(GString) body = g_string_new(NULL);
    g_autoptr(sqlite3_stmt) blocks =
        db_query(db, "SELECT payload FROM blocks WHERE memory_id = ? ORDER BY position", "s", id);
    while (db_step(blocks)) {
      g_autofree char *text = block_text(col_str(blocks, "payload"));
      append_part(body, text);
    }

    // Item titles are joined as they are, empty ones included, which is what
    // a plain " ".join did.
    g_autoptr(GString) titles = g_string_new(NULL);
    g_autoptr(sqlite3_stmt) items = db_query(db, "SELECT title FROM items WHERE memory_id = ?", "s", id);
    for (bool first = true; db_step(items); first = false) {
      if (!first)
        g_string_append_c(titles, ' ');
      g_string_append(titles, col_str(items, "title"));
    }

    // Tags belong in the index: they are what the model decided this capture
    // is about, and the labels on the filter chips -- typing one should find
    // the same memories the chip does.
    g_autoptr(GString) tags = g_string_new(NULL);
    g_autoptr(sqlite3_stmt) tag_rows = db_query(db, "SELECT tag FROM tags WHERE memory_id = ?", "s", id);
    for (bool first = true; db_step(tag_rows); first = false) {
      if (!first)
        g_string_append_c(tags, ' ');
      g_string_append(tags, col_str(tag_rows, "tag"));
    }

    g_autoptr(GString) all = g_string_new(NULL);
    append_part(all, body->str);
    append_part(all, titles->str);
    append_part(all, tags->str);

    const char *title = col_str(targets, "title");
    const char *lede = col_str(targets, "lede");
    const char *ocr = col_str(targets, "ocr_text");
    g_autoptr(sqlite3_stmt) insert = db_query(db,
        "INSERT INTO memories_fts (memory_id, title, lede, body, ocr_text) "
        "VALUES (?,?,?,?,?)",
        "sssss", id, title ? title : "", lede ? lede : "", all->str, ocr ? ocr : "");
    db_step(insert);
  }
  db_exec(db, "COMMIT");
}

// --- dimensions

bool image_size(const char *path, int64_t *width, int64_t *height) {
  if (!has("ffprobe"))
    return false;
  const char *argv[] = { "ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
    "stream=width,height", "-of", "csv=p=0:s=x", path, NULL };
  g_auto(ProcResult) probe = proc_run(argv, NULL, 10);
  g_strstrip(probe.out);
  g_auto(GStrv) parts = g_strsplit(probe.out, "x", 3);
  if (!parts[0] || !parts[1])
    return false;
  char *end_w = NULL, *end_h = NULL;
  *width = g_ascii_strtoll(g_strstrip(parts[0]), &end_w, 10);
  *height = g_ascii_strtoll(g_strstrip(parts[1]), &end_h, 10);
  if (*end_w || *end_h || end_w == parts[0] || end_h == parts[1])
    return false;
  return *width > 0 && *height > 0;
}

// Measure image attachments recorded before dimensions were stored. A file
// that has gone missing is skipped rather than treated as an error: the row is
// still a valid memory.
int backfill_dimensions(sqlite3 *db) {
  int filled = 0;
  g_autoptr(sqlite3_stmt) rows = db_query(db,
      "SELECT id, rel_path FROM attachments WHERE kind = 'image' "
      "AND (width IS NULL OR height IS NULL)",
      NULL);
  while (db_step(rows)) {
    g_autofree char *path = data_path(col_str(rows, "rel_path"));
    int64_t width = 0, height = 0;
    if (!g_file_test(path, G_FILE_TEST_EXISTS) || !image_size(path, &width, &height))
      continue;
    g_autoptr(sqlite3_stmt) update = db_query(db, "UPDATE attachments SET width = ?, height = ? WHERE id = ?",
        "iis", width, height, col_str(rows, "id"));
    db_step(update);
    filled++;
  }
  return filled;
}

// --- index.json

static json_object *event_entry(sqlite3 *db, sqlite3_stmt *row) {
  const char *memory_id = col_str(row, "memory_id");
  g_autofree char *domain = source_domain(db, memory_id);
  g_autoptr(sqlite3_stmt) thumb = db_query(db,
      "SELECT thumb_path FROM attachments WHERE memory_id = ? AND kind = 'image' LIMIT 1", "s", memory_id);
  g_autofree char *thumb_path =
      db_step(thumb) && col_str(thumb, "thumb_path") && *col_str(thumb, "thumb_path")
      ? data_path(col_str(thumb, "thumb_path"))
      : NULL;

  json_object *event = json_object_new_object();
  json_object_object_add(event, "id", json_str(col_str(row, "id")));
  json_object_object_add(event, "memoryId", json_str(memory_id));
  json_object_object_add(event, "title", json_str(col_str(row, "title")));
  json_object_object_add(event, "startsAt", json_str(col_str(row, "starts_at")));
  json_object_object_add(event, "endsAt", json_str(col_str(row, "ends_at")));
  json_object_object_add(event, "allDay", json_object_new_boolean(col_int(row, "all_day") != 0));
  json_object_object_add(event, "location", json_str_or_empty(col_str(row, "location")));
  json_object_object_add(event, "domain", json_str_or_empty(domain));
  json_object_object_add(event, "thumb", json_str_or_empty(thumb_path));
  return event;
}

static json_object *todo_entry(sqlite3_stmt *row, bool suggestion) {
  json_object *todo = json_object_new_object();
  json_object_object_add(todo, "id", json_str(col_str(row, "id")));
  json_object_object_add(todo, "memoryId", json_str(col_str(row, "memory_id")));
  json_object_object_add(todo, "title", json_str(col_str(row, "title")));
  json_object_object_add(todo, "dueAt", json_str(col_str(row, "due_at")));
  json_object_object_add(todo, "completedAt", suggestion ? NULL : json_str(col_str(row, "completed_at")));
  json_object_object_add(todo, "status", json_str(col_str(row, "status")));
  return todo;
}

static json_object *collection_entries(sqlite3 *db) {
  json_object *out = json_object_new_array();
  g_autoptr(sqlite3_stmt) rows = db_query(db,
      "SELECT c.id, c.name, COUNT(mc.memory_id) AS n FROM collections c "
      "LEFT JOIN memory_collections mc ON mc.collection_id = c.id "
      "GROUP BY c.id ORDER BY c.name",
      NULL);
  while (db_step(rows)) {
    // Up to four thumbnails, so a tile can show what is in it rather than
    // just how many.
    json_object *thumbs = json_object_new_array();
    g_autoptr(sqlite3_stmt) t = db_query(db,
        "SELECT a.thumb_path FROM attachments a "
        "JOIN memory_collections mc ON mc.memory_id = a.memory_id "
        "JOIN memories m ON m.id = a.memory_id "
        "WHERE mc.collection_id = ? AND a.kind = 'image' "
        "AND a.thumb_path IS NOT NULL AND m.status = 'ready' "
        "ORDER BY m.created_at DESC LIMIT 4",
        "s", col_str(rows, "id"));
    while (db_step(t)) {
      g_autofree char *path = data_path(col_str(t, "thumb_path"));
      json_object_array_add(thumbs, json_object_new_string(path));
    }
    json_object *entry = json_object_new_object();
    json_object_object_add(entry, "id", json_str(col_str(rows, "id")));
    json_object_object_add(entry, "name", json_str(col_str(rows, "name")));
    json_object_object_add(entry, "count", json_object_new_int64(col_int(rows, "n")));
    json_object_object_add(entry, "thumbs", thumbs);
    json_object_array_add(out, entry);
  }
  return out;
}

// Entries due by the end of the local day and not done.
static int64_t due_today(json_object *entries, const char *key, GDateTime *today_end) {
  int64_t count = 0;
  for (size_t i = 0; i < json_object_array_length(entries); i++) {
    json_object *entry = json_object_array_get_idx(entries, i);
    g_autoptr(GDateTime) when = parse_iso(json_get_str(entry, key));
    if (when && g_date_time_compare(when, today_end) <= 0 && !json_get_str(entry, "completedAt"))
      count++;
  }
  return count;
}

static json_object *build_index(sqlite3 *db) {
  json_object *memories = json_object_new_array();
  {
    g_autoptr(sqlite3_stmt) rows = db_query(db,
        "SELECT * FROM memories WHERE status = 'ready' "
        "ORDER BY created_at DESC LIMIT 500",
        NULL);
    while (db_step(rows))
      json_object_array_add(memories, memory_card(db, rows));
  }

  json_object *events = json_object_new_array();
  {
    g_autoptr(sqlite3_stmt) rows = db_query(db,
        "SELECT i.*, m.title AS memory_title FROM items i "
        "JOIN memories m ON m.id = i.memory_id "
        "WHERE i.kind = 'event' AND i.status = 'active' "
        "ORDER BY i.starts_at LIMIT 50",
        NULL);
    while (db_step(rows))
      json_object_array_add(events, event_entry(db, rows));
  }

  // Open ones only: a ticked-off to-do appeared under "No open to-dos" and
  // inflated the bar badge, which counts this list.
  json_object *todos = json_object_new_array();
  {
    g_autoptr(sqlite3_stmt) rows = db_query(db,
        "SELECT * FROM items WHERE kind = 'todo' AND status = 'active' "
        "AND completed_at IS NULL ORDER BY due_at IS NULL, due_at LIMIT 200",
        NULL);
    while (db_step(rows))
      json_object_array_add(todos, todo_entry(rows, false));
  }

  // Its own list: the bar badge and the digest count what the user has
  // accepted, and a suggestion is not that yet.
  json_object *suggestions = json_object_new_array();
  {
    g_autoptr(sqlite3_stmt) rows = db_query(db,
        "SELECT * FROM items WHERE kind = 'todo' AND status = 'suggested' "
        "ORDER BY created_at DESC LIMIT 200",
        NULL);
    while (db_step(rows))
      json_object_array_add(suggestions, todo_entry(rows, true));
  }

  // The end of the local day: whoever reads the digest means their midnight.
  g_autoptr(GDateTime) now = now_utc();
  g_autoptr(GDateTime) local = g_date_time_to_local(now);
  g_autoptr(GDateTime) today_end =
      g_date_time_new(g_date_time_get_timezone(local), g_date_time_get_year(local),
          g_date_time_get_month(local), g_date_time_get_day_of_month(local), 23, 59, 59);

  g_autoptr(sqlite3_stmt) counts = db_query(db,
      "SELECT SUM(ai_status = 'pending') AS pending, "
      "SUM(ai_status = 'failed') AS failed FROM memories",
      NULL);
  db_step(counts);

  json_object *digest = json_object_new_object();
  json_object_object_add(digest, "events", json_object_new_int64(due_today(events, "startsAt", today_end)));
  json_object_object_add(digest, "todos", json_object_new_int64(due_today(todos, "dueAt", today_end)));

  json_object *alarms = json_object_new_array();
  {
    // The id and the time, nothing else. The shell hands the id straight back
    // to `reminder fire`, so no text a model wrote travels through index.json
    // to reach a toast.
    g_autoptr(sqlite3_stmt) rows =
        db_query(db, "SELECT r.id, r.fire_at " LIVE_REMINDER " ORDER BY r.fire_at LIMIT 200", NULL);
    while (db_step(rows)) {
      json_object *alarm = json_object_new_object();
      json_object_object_add(alarm, "id", json_str(col_str(rows, "id")));
      json_object_object_add(alarm, "fireAt", json_str(col_str(rows, "fire_at")));
      json_object_array_add(alarms, alarm);
    }
  }

  g_autofree char *generated = iso(now);
  json_object *index = json_object_new_object();
  json_object_object_add(index, "version", json_object_new_int(INDEX_VERSION));
  json_object_object_add(index, "generatedAt", json_object_new_string(generated));
  // The bar menu gates its voice entry on this.
  json_object_object_add(index, "voiceAvailable", json_object_new_boolean(has("voxtype")));
  json_object_object_add(index, "facets", build_facets(memories));
  json_object_object_add(index, "pendingCount", json_object_new_int64(col_int(counts, "pending")));
  json_object_object_add(index, "failedCount", json_object_new_int64(col_int(counts, "failed")));
  json_object_object_add(
      index, "memoryCount", json_object_new_int64((int64_t)json_object_array_length(memories)));
  json_object_object_add(index, "digest", digest);
  json_object_object_add(index, "memories", memories);
  json_object_object_add(index, "events", events);
  json_object_object_add(index, "todos", todos);
  json_object_object_add(index, "suggestions", suggestions);
  json_object_object_add(index, "collections", collection_entries(db));
  // What the shell arms its timer against. Last, because it is the only key
  // here the shell acts on rather than renders.
  json_object_object_add(index, "alarms", alarms);
  return index;
}

void write_index(sqlite3 *db) {
  const Paths *p = paths();
  g_mkdir_with_parents(p->state_dir, 0777);
  g_autoptr(json_object) index = build_index(db);
  if (!write_json_file(p->index_path, index))
    die(1, "could not write %s", p->index_path);
}
