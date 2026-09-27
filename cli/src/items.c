// Blocks and the to-dos and events that hang off them.
#include "omoide.h"

enum {
  MAX_REMINDERS = 4,   // per item, and every one interrupts someone
  MAX_MEMORY_REMINDERS = 12,   // and per capture, which is the number that matters
  MAX_TITLE = 200,
};

static int64_t next_position(sqlite3 *db, const char *memory_id) {
  g_autoptr(sqlite3_stmt) row = db_query(
      db, "SELECT COALESCE(MAX(position), -1) + 1 AS n FROM blocks WHERE memory_id = ?", "s", memory_id);
  db_step(row);
  return col_int(row, "n");
}

char *add_block(
    sqlite3 *db, const char *memory_id, const char *type, json_object *payload, const char *origin) {
  g_autoptr(json_object) owned = payload;
  char *id = new_id(NULL);
  g_autoptr(sqlite3_stmt) insert = db_query(db,
      "INSERT INTO blocks (id, memory_id, position, type, payload, origin) "
      "VALUES (?,?,?,?,?,?)",
      "ssisss", id, memory_id, next_position(db, memory_id), type,
      json_object_to_json_string_ext(owned, JSON_C_TO_STRING_PLAIN | JSON_C_TO_STRING_NOSLASHESCAPE), origin);
  db_step(insert);
  return id;
}

void set_block_payload(sqlite3 *db, const char *block_id, json_object *payload) {
  g_autoptr(json_object) owned = payload;
  g_autoptr(sqlite3_stmt) update = db_query(db, "UPDATE blocks SET payload = ? WHERE id = ?", "ss",
      json_object_to_json_string_ext(owned, JSON_C_TO_STRING_PLAIN | JSON_C_TO_STRING_NOSLASHESCAPE),
      block_id);
  db_step(update);
}

// A string field of a spec, or NULL: a spec is JSON, and anything else in a
// text column would be a lie about what was asked for.
static const char *spec_str(json_object *spec, const char *key) {
  return json_get_str(spec, key);
}

char *create_item(
    sqlite3 *db, const char *memory_id, const char *block_id, json_object *spec, const char *source) {
  char *item_id = new_id(NULL);
  // An inferred to-do is a SUGGESTION: no alarm, and it waits in its own
  // section of Tasks until the user accepts it. Only what the note actually
  // asked for becomes a live to-do straight away.
  json_object *suggested = json_get(spec, "suggested");
  const bool inferred = suggested ? truthy(suggested) : true;
  const char *kind = spec_str(spec, "kind") ? spec_str(spec, "kind") : "todo";
  const bool event = g_str_equal(kind, "event");
  // Only a TO-DO waits to be accepted. An event is a fact the capture states,
  // so it goes straight into the calendar surfaces, with a default alarm
  // below when it has a time and the note asked for none.
  const char *status = inferred && g_str_equal(kind, "todo") ? "suggested" : "active";

  g_autofree char *title = clean_text(json_get(spec, "title"), MAX_TITLE);
  g_autofree char *created = iso_now();
  g_autoptr(sqlite3_stmt) insert = db_query(db,
      "INSERT INTO items (id, memory_id, block_id, kind, title, notes, due_at,"
      " starts_at, ends_at, all_day, location, map_url, status, source, created_at)"
      " VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
      "sssssssssisssss", item_id, memory_id, block_id, kind, *title ? title : "Untitled",
      spec_str(spec, "notes"), spec_str(spec, "due_at"), spec_str(spec, "starts_at"),
      spec_str(spec, "ends_at"), (int64_t)(truthy(json_get(spec, "all_day")) ? 1 : 0),
      spec_str(spec, "location"), spec_str(spec, "map_url"), status, source, created);
  db_step(insert);

  const char *due = spec_str(spec, "due_at");
  g_autoptr(GDateTime) anchor = parse_iso(due && *due ? due : spec_str(spec, "starts_at"));

  // Bounded here as well as in validation: this is the last thing before the
  // reminders table, and it is reached from the editors too.
  g_autoptr(json_object) requested = json_object_new_array();
  json_object *remind = json_get(spec, "remind");
  for (size_t i = 0; json_object_is_type(remind, json_type_array) && i < json_object_array_length(remind)
      && i < MAX_REMINDERS;
      i++)
    json_object_array_add(requested, json_object_get(json_object_array_get_idx(remind, i)));

  const bool asked = json_object_array_length(requested) > 0;
  if (event) {
    // An event gets a reminder whether or not the note asked for one: being
    // told before a thing you are going to is the reason for capturing it.
    if (!asked && anchor)
      json_object_array_add(requested, json_tokener_parse("{\"offset_min\": -30}"));
  } else if (inferred) {
    // Nothing the model merely inferred puts a notification on someone's
    // machine; promoting it is what schedules the alarm.
    json_object_array_del_idx(requested, 0, json_object_array_length(requested));
  } else if (!asked && anchor) {
    // An explicit dated to-do gets one alarm at its due time.
    json_object_array_add(requested, json_tokener_parse("{\"offset_min\": 0}"));
  }

  // Last, because the branches above can ADD a default alarm: capping before
  // them would be undone by them. Per-item caps also multiply: eight events
  // at four alarms each is thirty-two toasts from one screenshot. So this
  // counts across the whole memory.
  g_autoptr(sqlite3_stmt) count = db_query(db,
      "SELECT COUNT(*) AS n FROM reminders r JOIN items i ON i.id = r.item_id "
      "WHERE i.memory_id = ?",
      "s", memory_id);
  db_step(count);
  const int64_t room = MAX(0, MAX_MEMORY_REMINDERS - col_int(count, "n"));

  for (size_t i = 0; i < json_object_array_length(requested) && (int64_t)i < room; i++) {
    json_object *entry = json_object_array_get_idx(requested, i);
    if (!json_object_is_type(entry, json_type_object))
      continue;
    g_autoptr(GDateTime) absolute = parse_iso(json_get_str(entry, "at"));
    json_object *offset_value = json_get(entry, "offset_min");
    int64_t offset = 0;
    bool relative = false;
    g_autoptr(GDateTime) fire_at = NULL;
    if (absolute) {
      fire_at = g_date_time_ref(absolute);
    } else if (anchor && offset_value && !json_object_is_type(offset_value, json_type_null)) {
      if (!as_int(offset_value, &offset))
        continue;
      relative = true;
      fire_at = g_date_time_add_minutes(anchor, (int)offset);
    } else {
      continue;
    }
    g_autofree char *reminder_id = new_id(NULL);
    g_autofree char *when = iso(fire_at);
    g_autofree char *offset_text = relative ? g_strdup_printf("%" G_GINT64_FORMAT, offset) : NULL;
    g_autoptr(sqlite3_stmt) reminder = db_query(db,
        "INSERT INTO reminders (id, item_id, fire_at, trigger_offset_min, status) "
        "VALUES (?,?,?,CAST(? AS INTEGER),'pending')",
        "ssss", reminder_id, item_id, when, offset_text);
    db_step(reminder);
  }
  return item_id;
}

// Close the gaps a deletion leaves, so `position` stays 0..n-1.
void renumber_blocks(sqlite3 *db, const char *memory_id) {
  g_autoptr(GPtrArray) ids = g_ptr_array_new_with_free_func(g_free);
  {
    g_autoptr(sqlite3_stmt) rows =
        db_query(db, "SELECT id FROM blocks WHERE memory_id = ? ORDER BY position", "s", memory_id);
    while (db_step(rows))
      g_ptr_array_add(ids, g_strdup(col_str(rows, "id")));
  }
  for (size_t i = 0; i < ids->len; i++) {
    g_autoptr(sqlite3_stmt) update = db_query(db, "UPDATE blocks SET position = ? WHERE id = ?", "is",
        (int64_t)i, (const char *)g_ptr_array_index(ids, i));
    db_step(update);
  }
}

// Recompute relative alarms after an item's time moved. trigger_offset_min is
// kept rather than baked away precisely so this works.
void reschedule_item(sqlite3 *db, const char *item_id) {
  g_autoptr(sqlite3_stmt) item = db_query(db, "SELECT * FROM items WHERE id = ?", "s", item_id);
  if (!db_step(item))
    return;
  const char *due = col_str(item, "due_at");
  g_autoptr(GDateTime) anchor = parse_iso(due && *due ? due : col_str(item, "starts_at"));
  if (!anchor)
    return;
  g_autoptr(sqlite3_stmt) rows = db_query(
      db, "SELECT * FROM reminders WHERE item_id = ? AND trigger_offset_min IS NOT NULL", "s", item_id);
  while (db_step(rows)) {
    g_autoptr(GDateTime) fire_at = g_date_time_add_minutes(anchor, (int)col_int(rows, "trigger_offset_min"));
    g_autofree char *when = iso(fire_at);
    g_autoptr(sqlite3_stmt) update =
        db_query(db, "UPDATE reminders SET fire_at = ? WHERE id = ?", "ss", when, col_str(rows, "id"));
    db_step(update);
  }
}

json_object *item_payload(sqlite3 *db, sqlite3_stmt *item) {
  const char *id = col_str(item, "id");
  g_autoptr(sqlite3_stmt) memory =
      db_query(db, "SELECT id, title FROM memories WHERE id = ?", "s", col_str(item, "memory_id"));
  const bool has_memory = db_step(memory);

  json_object *reminders = json_object_new_array();
  g_autoptr(sqlite3_stmt) rows =
      db_query(db, "SELECT * FROM reminders WHERE item_id = ? ORDER BY fire_at", "s", id);
  while (db_step(rows)) {
    json_object *r = json_object_new_object();
    json_object_object_add(r, "id", json_str(col_str(rows, "id")));
    json_object_object_add(r, "fireAt", json_str(col_str(rows, "fire_at")));
    json_object_object_add(r, "offsetMin",
        col_null(rows, "trigger_offset_min") ? NULL
                                             : json_object_new_int64(col_int(rows, "trigger_offset_min")));
    json_object_object_add(r, "status", json_str(col_str(rows, "status")));
    json_object_array_add(reminders, r);
  }

  json_object *out = json_object_new_object();
  json_object_object_add(out, "id", json_str(id));
  json_object_object_add(out, "kind", json_str(col_str(item, "kind")));
  json_object_object_add(out, "title", json_str(col_str(item, "title")));
  json_object_object_add(out, "notes", json_str_or_empty(col_str(item, "notes")));
  json_object_object_add(out, "dueAt", json_str(col_str(item, "due_at")));
  json_object_object_add(out, "startsAt", json_str(col_str(item, "starts_at")));
  json_object_object_add(out, "endsAt", json_str(col_str(item, "ends_at")));
  json_object_object_add(out, "allDay", json_object_new_boolean(col_int(item, "all_day") != 0));
  json_object_object_add(out, "location", json_str_or_empty(col_str(item, "location")));
  json_object_object_add(out, "mapUrl", json_str_or_empty(col_str(item, "map_url")));
  json_object_object_add(out, "status", json_str(col_str(item, "status")));
  json_object_object_add(out, "completedAt", json_str(col_str(item, "completed_at")));
  json_object_object_add(out, "source", json_str(col_str(item, "source")));
  json_object_object_add(out, "memoryId", json_str(col_str(item, "memory_id")));
  json_object_object_add(
      out, "memoryTitle", has_memory ? json_str(col_str(memory, "title")) : json_object_new_string(""));
  json_object_object_add(out, "reminders", reminders);
  return out;
}
