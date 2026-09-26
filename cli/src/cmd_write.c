// Mutations: to-dos and events, alarms, collections, links, blocks, memories.
#include "omoide.h"

static void run_update(sqlite3 *db, const char *sql, const char *types, const char *a,
                       const char *b) {
  g_autoptr(sqlite3_stmt) stmt = types[1] ? db_query(db, sql, types, a, b)
                                          : db_query(db, sql, types, a);
  db_step(stmt);
}

static int64_t reminder_count(sqlite3 *db, const char *item_id) {
  g_autoptr(sqlite3_stmt) row = db_query(
    db, "SELECT COUNT(*) AS n FROM reminders WHERE item_id = ?", "s", item_id);
  db_step(row);
  return col_int(row, "n");
}

static void insert_reminder(sqlite3 *db, const char *item_id, GDateTime *fire_at,
                            const char *offset) {
  g_autofree char *id = new_id(NULL);
  g_autofree char *when = iso(fire_at);
  g_autoptr(sqlite3_stmt) insert = db_query(
    db, "INSERT INTO reminders (id, item_id, fire_at, trigger_offset_min, status) "
        "VALUES (?,?,?,CAST(? AS INTEGER),'pending')", "ssss", id, item_id, when, offset);
  db_step(insert);
}

// A time as a person typed it: a timestamp, or failing that the grammar.
static GDateTime *read_when(const char *text) {
  GDateTime *when = parse_iso(text);
  return when ? when : parse_when(text);
}

static const char *const ITEM_ACTIONS[] = { "get", "add", "edit", "promote", "complete",
                                            "reopen", "cancel", NULL };
static const char *const KINDS[] = { "todo", "event", NULL };

int cmd_item(int argc, char **argv) {
  g_autofree char *id = NULL, *memory = NULL, *kind = NULL, *title = NULL, *at = NULL,
                  *notes = NULL;
  gboolean clear_at = FALSE;
  const GOptionEntry entries[] = {
    { "id", 0, 0, G_OPTION_ARG_STRING, &id, "the item", "ID" },
    { "memory", 0, 0, G_OPTION_ARG_STRING, &memory, "the memory, for add", "ID" },
    { "kind", 0, 0, G_OPTION_ARG_STRING, &kind, "todo or event", "KIND" },
    { "title", 0, 0, G_OPTION_ARG_STRING, &title, NULL, "TEXT" },
    { "at", 0, 0, G_OPTION_ARG_STRING, &at, NULL, "WHEN" },
    { "notes", 0, 0, G_OPTION_ARG_STRING, &notes, NULL, "TEXT" },
    { "clear-at", 0, 0, G_OPTION_ARG_NONE, &clear_at, "drop the date, making it an undated to-do", NULL },
    G_OPTION_ENTRY_NULL
  };
  parse_options("item", entries, 1, &argc, &argv);
  const char *action = positional(argc, argv);
  require_option("item", "action", action);
  require_choice("item", "action", action, ITEM_ACTIONS);
  if (kind)
    require_choice("item", "--kind", kind, KINDS);
  const char *item_kind = kind ? kind : "todo";

  if (g_str_equal(action, "get")) {
    sqlite3 *db = db_open(false);
    g_autoptr(sqlite3_stmt) item = db_query(db, "SELECT * FROM items WHERE id = ?", "s", id);
    if (!db_step(item))
      die(1, "no such item: %s", id ? id : "None");
    emit(item_payload(db, item));
    return 0;
  }

  sqlite3 *db = db_open(true);
  if (g_str_equal(action, "add")) {
    g_autoptr(json_object) spec = json_object_new_object();
    json_object_object_add(spec, "kind", json_object_new_string(item_kind));
    json_object_object_add(spec, "title", json_str(title));
    json_object_object_add(spec, "suggested", json_object_new_boolean(false));
    g_autoptr(GDateTime) when = at && *at ? read_when(at) : NULL;
    if (when) {
      g_autofree char *stamp = iso(when);
      json_object_object_add(spec, g_str_equal(item_kind, "todo") ? "due_at" : "starts_at",
                             json_object_new_string(stamp));
    }
    g_autofree char *item_id = create_item(db, memory, NULL, spec, "manual");
    json_object *out = json_object_new_object();
    json_object_object_add(out, "id", json_object_new_string(item_id));
    emit(out);
  } else {
    g_autoptr(sqlite3_stmt) item = db_query(db, "SELECT * FROM items WHERE id = ?", "s", id);
    if (!db_step(item))
      die(1, "no such item: %s", id ? id : "None");

    if (g_str_equal(action, "promote")) {
      run_update(db, "UPDATE items SET status = 'active' WHERE id = ?", "s", id, NULL);
      // A promoted item with a time and no alarm gets one, so accepting a
      // suggestion actually schedules something.
      const char *due = col_str(item, "due_at");
      g_autoptr(GDateTime) anchor = parse_iso(due && *due ? due : col_str(item, "starts_at"));
      if (anchor && !reminder_count(db, id))
        insert_reminder(db, id, anchor, NULL);
    } else if (g_str_equal(action, "complete")) {
      g_autofree char *stamp = iso_now();
      run_update(db, "UPDATE items SET completed_at = ? WHERE id = ?", "ss", stamp, id);
    } else if (g_str_equal(action, "reopen")) {
      run_update(db, "UPDATE items SET completed_at = NULL WHERE id = ?", "s", id, NULL);
      run_update(db, "UPDATE reminders SET status = 'pending' WHERE item_id = ? "
                     "AND status = 'cancelled'", "s", id, NULL);
    } else if (g_str_equal(action, "cancel")) {
      run_update(db, "UPDATE items SET status = 'cancelled' WHERE id = ?", "s", id, NULL);
    } else if (g_str_equal(action, "edit")) {
      if (title && *title)
        run_update(db, "UPDATE items SET title = ? WHERE id = ?", "ss", title, id);
      if (notes)
        run_update(db, "UPDATE items SET notes = ? WHERE id = ?", "ss", notes, id);
      // The column comes from a fixed pair, never from input.
      const bool todo = g_strcmp0(col_str(item, "kind"), "todo") == 0;
      if (clear_at) {
        // An undated to-do is valid, so clearing has to drop the alarms with
        // it rather than leaving them pointing at nothing.
        run_update(db, todo ? "UPDATE items SET due_at = NULL WHERE id = ?"
                            : "UPDATE items SET starts_at = NULL WHERE id = ?", "s", id, NULL);
        run_update(db, "DELETE FROM reminders WHERE item_id = ?", "s", id, NULL);
      } else if (at && *at) {
        g_autoptr(GDateTime) when = read_when(at);
        if (!when)
          die(1, "could not read a date from: %s", at);
        g_autofree char *stamp = iso(when);
        run_update(db, todo ? "UPDATE items SET due_at = ? WHERE id = ?"
                            : "UPDATE items SET starts_at = ? WHERE id = ?", "ss", stamp, id);
        if (!reminder_count(db, id))
          insert_reminder(db, id, when, NULL);
        reschedule_item(db, id);
      }
    }
  }
  g_autoptr(json_object) swept = sweep_reminders(db);
  write_index(db);
  shell_ipc(IPC_TARGET, "refresh", NULL);
  return 0;
}

static const char *const REMINDER_ACTIONS[] = { "add", "remove", "fire", NULL };

int cmd_reminder(int argc, char **argv) {
  g_autofree char *id = NULL, *item_id = NULL, *at = NULL, *offset_text = NULL;
  const GOptionEntry entries[] = {
    { "id", 0, 0, G_OPTION_ARG_STRING, &id, "the reminder", "ID" },
    { "item", 0, 0, G_OPTION_ARG_STRING, &item_id, "the item", "ID" },
    { "at", 0, 0, G_OPTION_ARG_STRING, &at, NULL, "WHEN" },
    { "offset", 0, 0, G_OPTION_ARG_STRING, &offset_text,
      "minutes relative to the item's time, e.g. -30", "MIN" },
    G_OPTION_ENTRY_NULL
  };
  parse_options("reminder", entries, 1, &argc, &argv);
  const char *action = positional(argc, argv);
  require_option("reminder", "action", action);
  require_choice("reminder", "action", action, REMINDER_ACTIONS);
  int64_t offset = 0;
  if (offset_text && !g_ascii_string_to_signed(offset_text, 10, INT32_MIN, INT32_MAX, &offset, NULL))
    die(2, "reminder: argument --offset: invalid int value: '%s'", offset_text);

  sqlite3 *db = db_open(true);
  if (g_str_equal(action, "add")) {
    g_autoptr(sqlite3_stmt) item = db_query(db, "SELECT * FROM items WHERE id = ?", "s", item_id);
    if (!db_step(item))
      die(1, "no such item: %s", item_id ? item_id : "None");
    const char *due = col_str(item, "due_at");
    g_autoptr(GDateTime) anchor = parse_iso(due && *due ? due : col_str(item, "starts_at"));
    if (offset_text) {
      if (!anchor)
        die(1, "an offset needs an item with a time");
      g_autoptr(GDateTime) fire_at = g_date_time_add_minutes(anchor, (int)offset);
      g_autofree char *minutes = g_strdup_printf("%" G_GINT64_FORMAT, offset);
      insert_reminder(db, item_id, fire_at, minutes);
    } else {
      g_autoptr(GDateTime) fire_at = read_when(at ? at : "");
      if (!fire_at)
        die(1, "could not read a time from --at");
      insert_reminder(db, item_id, fire_at, NULL);
    }
  } else if (g_str_equal(action, "remove")) {
    run_update(db, "DELETE FROM reminders WHERE id = ?", "s", id, NULL);
  } else {
    // The shell's timer went off. Whether the alarm is still owed is decided
    // here, not there, so a repeat is a no-op.
    if (!id)
      die(1, "fire needs --id");
    const char *outcome = fire_reminder(db, id);
    write_index(db);
    json_object *out = json_object_new_object();
    json_object_object_add(out, "id", json_object_new_string(id));
    json_object_object_add(out, "outcome", json_object_new_string(outcome));
    emit(out);
    return 0;
  }
  g_autoptr(json_object) swept = sweep_reminders(db);
  write_index(db);
  return 0;
}

static const char *const COLLECTION_ACTIONS[] = { "new", "add", "remove", "rename", "delete", NULL };

static char *collection_id(sqlite3 *db, const char *name) {
  g_autoptr(sqlite3_stmt) row = db_query(db, "SELECT id FROM collections WHERE name = ?", "s", name);
  return db_step(row) ? g_strdup(col_str(row, "id")) : NULL;
}

int cmd_collection(int argc, char **argv) {
  g_autofree char *name = NULL, *to = NULL, *memory = NULL;
  const GOptionEntry entries[] = {
    { "name", 0, 0, G_OPTION_ARG_STRING, &name, "the collection", "NAME" },
    { "to", 0, 0, G_OPTION_ARG_STRING, &to, "the new name, for rename", "NAME" },
    { "memory", 0, 0, G_OPTION_ARG_STRING, &memory, "the memory, for add and remove", "ID" },
    G_OPTION_ENTRY_NULL
  };
  parse_options("collection", entries, 1, &argc, &argv);
  const char *action = positional(argc, argv);
  require_option("collection", "action", action);
  require_choice("collection", "action", action, COLLECTION_ACTIONS);
  require_option("collection", "--name", name);

  sqlite3 *db = db_open(true);
  g_autofree char *stamp = iso_now();
  if (g_str_equal(action, "new")) {
    g_autofree char *id = new_id(NULL);
    g_autoptr(sqlite3_stmt) insert = db_query(
      db, "INSERT OR IGNORE INTO collections (id, name, created_at) VALUES (?,?,?)",
      "sss", id, name, stamp);
    db_step(insert);
  } else if (g_str_equal(action, "rename")) {
    g_autofree char *target = to ? strip_space(to) : g_strdup("");
    if (!*target)
      die(1, "rename needs --to");
    g_autofree char *id = collection_id(db, name);
    if (!id)
      die(1, "no such collection: %s", name);
    g_autoptr(sqlite3_stmt) clash = db_query(
      db, "SELECT id FROM collections WHERE name = ? AND id != ?", "ss", target, id);
    if (db_step(clash))
      die(2, "a collection called '%s' already exists", target);
    run_update(db, "UPDATE collections SET name = ? WHERE id = ?", "ss", target, id);
  } else if (g_str_equal(action, "delete")) {
    // The collection only. memory_collections cascades on the foreign key, so
    // the memberships go and every memory stays exactly where it was.
    g_autofree char *id = collection_id(db, name);
    if (!id)
      die(1, "no such collection: %s", name);
    run_update(db, "DELETE FROM collections WHERE id = ?", "s", id, NULL);
  } else {
    g_autofree char *id = collection_id(db, name);
    if (!id && g_str_equal(action, "add")) {
      id = new_id(NULL);
      g_autoptr(sqlite3_stmt) insert = db_query(
        db, "INSERT INTO collections (id, name, created_at) VALUES (?,?,?)", "sss", id, name, stamp);
      db_step(insert);
    } else if (!id) {
      die(1, "no such collection: %s", name);
    }
    if (g_str_equal(action, "add"))
      run_update(db, "INSERT OR IGNORE INTO memory_collections (memory_id, collection_id) "
                     "VALUES (?,?)", "ss", memory, id);
    else
      run_update(db, "DELETE FROM memory_collections WHERE memory_id = ? AND collection_id = ?",
                 "ss", memory, id);
  }
  write_index(db);
  shell_ipc(IPC_TARGET, "refresh", NULL);
  return 0;
}

static const char *const LINK_ACTIONS[] = { "add", "remove", NULL };

int cmd_link(int argc, char **argv) {
  g_autofree char *from = NULL, *to = NULL;
  const GOptionEntry entries[] = {
    { "from", 0, 0, G_OPTION_ARG_STRING, &from, NULL, "ID" },
    { "to", 0, 0, G_OPTION_ARG_STRING, &to, NULL, "ID" },
    G_OPTION_ENTRY_NULL
  };
  parse_options("link", entries, 1, &argc, &argv);
  const char *action = positional(argc, argv);
  require_option("link", "action", action);
  require_choice("link", "action", action, LINK_ACTIONS);
  require_option("link", "--from", from);
  require_option("link", "--to", to);

  sqlite3 *db = db_open(true);
  // One row per pair: the ids are ordered so (a,b) and (b,a) cannot both exist.
  const bool ordered = strcmp(from, to) <= 0;
  const char *low = ordered ? from : to, *high = ordered ? to : from;
  if (g_str_equal(action, "add")) {
    g_autofree char *stamp = iso_now();
    g_autoptr(sqlite3_stmt) insert = db_query(
      db, "INSERT OR IGNORE INTO links (from_id, to_id, created_at) VALUES (?,?,?)",
      "sss", low, high, stamp);
    db_step(insert);
  } else {
    run_update(db, "DELETE FROM links WHERE from_id = ? AND to_id = ?", "ss", low, high);
  }
  write_index(db);
  return 0;
}

static const char *const BLOCK_ACTIONS[] = { "set", "delete", NULL };

// Edit or remove one block. An edit marks the row so a later AI pass cannot
// silently overwrite what the user corrected.
int cmd_block(int argc, char **argv) {
  g_autofree char *id = NULL, *payload_text = NULL;
  const GOptionEntry entries[] = {
    { "id", 0, 0, G_OPTION_ARG_STRING, &id, "the block", "ID" },
    { "payload", 0, 0, G_OPTION_ARG_STRING, &payload_text, "the new payload, as JSON", "JSON" },
    G_OPTION_ENTRY_NULL
  };
  parse_options("block", entries, 1, &argc, &argv);
  const char *action = positional(argc, argv);
  require_option("block", "action", action);
  require_choice("block", "action", action, BLOCK_ACTIONS);
  require_option("block", "--id", id);

  sqlite3 *db = db_open(true);
  g_autofree char *memory_id = NULL;
  {
    g_autoptr(sqlite3_stmt) block = db_query(db, "SELECT * FROM blocks WHERE id = ?", "s", id);
    if (!db_step(block))
      die(1, "no such block: %s", id);
    memory_id = g_strdup(col_str(block, "memory_id"));
  }
  if (g_str_equal(action, "delete")) {
    run_update(db, "DELETE FROM blocks WHERE id = ?", "s", id, NULL);
    renumber_blocks(db, memory_id);
  } else {
    g_autoptr(json_tokener) tok = json_tokener_new();
    json_tokener_set_flags(tok, JSON_TOKENER_STRICT);
    if (!payload_text)
      die(1, "--payload must be JSON");
    g_autoptr(json_object) payload = json_tokener_parse_ex(tok, payload_text,
                                                           (int)strlen(payload_text));
    // A literal null parses to no object at all, and is still valid JSON.
    if (json_tokener_get_error(tok) != json_tokener_success)
      die(1, "--payload must be JSON");
    for (const char *rest = payload_text + json_tokener_get_parse_end(tok); *rest; rest++)
      if (!g_ascii_isspace(*rest))
        die(1, "--payload must be JSON");
    run_update(db, "UPDATE blocks SET payload = ?, edited = 1 WHERE id = ?", "ss",
               payload ? json_object_to_json_string_ext(payload, JSON_C_TO_STRING_PLAIN
                                                        | JSON_C_TO_STRING_NOSLASHESCAPE)
                       : "null", id);
  }
  refresh_fts(db, memory_id);
  write_index(db);
  shell_ipc(IPC_TARGET, "refresh", NULL);
  return 0;
}

int cmd_delete(int argc, char **argv) {
  g_autofree char *id = NULL;
  const GOptionEntry entries[] = {
    { "id", 0, 0, G_OPTION_ARG_STRING, &id, "the memory", "ID" },
    G_OPTION_ENTRY_NULL
  };
  parse_options("delete", entries, 0, &argc, &argv);
  require_option("delete", "--id", id);
  sqlite3 *db = db_open(true);
  discard(db, id, false);
  write_index(db);
  shell_ipc(IPC_TARGET, "refresh", NULL);
  return 0;
}

// Edit a memory's own fields. The blocks are `block set`'s business.
int cmd_memory(int argc, char **argv) {
  g_autofree char *id = NULL, *title = NULL, *lede = NULL;
  const GOptionEntry entries[] = {
    { "id", 0, 0, G_OPTION_ARG_STRING, &id, "the memory", "ID" },
    { "title", 0, 0, G_OPTION_ARG_STRING, &title, NULL, "TEXT" },
    { "lede", 0, 0, G_OPTION_ARG_STRING, &lede, NULL, "TEXT" },
    G_OPTION_ENTRY_NULL
  };
  parse_options("memory", entries, 0, &argc, &argv);
  require_option("memory", "--id", id);
  sqlite3 *db = db_open(true);
  {
    g_autoptr(sqlite3_stmt) memory = db_query(db, "SELECT id FROM memories WHERE id = ?", "s", id);
    if (!db_step(memory))
      die(1, "no such memory: %s", id);
  }
  g_autofree char *stamp = iso_now();
  if (title) {
    g_autofree char *clean = strip_space(title);
    if (!*clean)
      die(2, "a memory needs a title");
    g_autoptr(sqlite3_stmt) update = db_query(
      db, "UPDATE memories SET title = ?, updated_at = ? WHERE id = ?", "sss", clean, stamp, id);
    db_step(update);
  }
  if (lede) {
    g_autofree char *clean = strip_space(lede);
    g_autoptr(sqlite3_stmt) update = db_query(
      db, "UPDATE memories SET lede = ?, updated_at = ? WHERE id = ?", "sss", clean, stamp, id);
    db_step(update);
  }
  refresh_fts(db, id);
  write_index(db);
  shell_ipc(IPC_TARGET, "refresh", NULL);
  json_object *out = json_object_new_object();
  json_object_object_add(out, "id", json_object_new_string(id));
  emit(out);
  return 0;
}
