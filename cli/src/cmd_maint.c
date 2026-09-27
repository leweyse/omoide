// Upkeep: rebuilding what is derived, and the startup reconciliation.
#include "omoide.h"

#include <glib/gstdio.h>
#include <signal.h>

int cmd_reindex(int argc, char **argv) {
  parse_options("reindex", NULL, 0, &argc, &argv);
  sqlite3 *db = db_open(true);
  // Before the shell is told, not after: the cards carry each capture's aspect,
  // so an unmeasured row would render with aspect 0 until the next rebuild.
  const int measured = backfill_dimensions(db);
  refresh_fts(db, NULL);
  shell_ipc(IPC_TARGET, "refresh", NULL);
  json_object *out = json_object_new_object();
  json_object_object_add(out, "reindexed", json_object_new_boolean(true));
  json_object_object_add(out, "version", json_object_new_int(INDEX_VERSION));
  json_object_object_add(out, "measured", json_object_new_int(measured));
  emit(out);
  return 0;
}

// Is an enrichment for this memory actually alive?
static bool commit_running(const char *memory_id) {
  g_autofree char *path = commit_pidfile(memory_id);
  g_autofree char *text = NULL;
  if (!g_file_get_contents(path, &text, NULL, NULL))
    return false;
  char *end = NULL;
  const gint64 pid = g_ascii_strtoll(g_strstrip(text), &end, 10);
  if (end == text || *end)
    return false;
  return kill((pid_t)pid, 0) == 0;
}

// Resolve enrichments that will never finish. A commit killed part-way leaves
// ai_status='pending' with no process behind it, and the bar then shows a scan
// line forever.
//
// Detected by the process being gone rather than an elapsed-time guess: a
// timeout either resolves a live model call too early or leaves a dead one
// spinning. Marking them failed is honest: the capture itself is intact, and
// silently re-running the model would spend tokens nobody asked to spend.
static int64_t sweep_stalled(sqlite3 *db) {
  g_autoptr(GPtrArray) pending = g_ptr_array_new_with_free_func(g_free);
  {
    g_autoptr(sqlite3_stmt) rows = db_query(db, "SELECT id FROM memories WHERE ai_status = 'pending'", NULL);
    while (db_step(rows))
      g_ptr_array_add(pending, g_strdup(col_str(rows, "id")));
  }
  int64_t resolved = 0;
  for (size_t i = 0; i < pending->len; i++) {
    const char *id = g_ptr_array_index(pending, i);
    if (commit_running(id))
      continue;
    g_autoptr(sqlite3_stmt) mark = db_query(db,
        "UPDATE memories SET ai_status = 'failed', "
        "ai_error = 'the enrichment stopped before it finished' WHERE id = ?",
        "s", id);
    db_step(mark);
    g_autofree char *pidfile = commit_pidfile(id);
    g_unlink(pidfile);
    resolved++;
  }
  return resolved;
}

// Discard drafts whose compose overlay is gone. A draft exists only while its
// overlay is on screen, so one that outlives the shell just holds a blob on
// disk. The age cutoff avoids racing a capture genuinely mid-picker when the
// plugin reloads.
static int64_t sweep_drafts(sqlite3 *db) {
  g_autoptr(GDateTime) now = now_utc();
  g_autoptr(GDateTime) before = g_date_time_add_minutes(now, -10);
  g_autofree char *cutoff = iso(before);
  g_autoptr(GPtrArray) stale = g_ptr_array_new_with_free_func(g_free);
  {
    g_autoptr(sqlite3_stmt) rows =
        db_query(db, "SELECT id FROM memories WHERE status = 'draft' AND created_at < ?", "s", cutoff);
    while (db_step(rows))
      g_ptr_array_add(stale, g_strdup(col_str(rows, "id")));
  }
  for (size_t i = 0; i < stale->len; i++)
    discard(db, g_ptr_array_index(stale, i), true);
  return (int64_t)stale->len;
}

// Startup reconciliation: late alarms delivered, dead drafts swept.
int cmd_sweep(int argc, char **argv) {
  parse_options("sweep", NULL, 0, &argc, &argv);
  sqlite3 *db = db_open(true);
  const int64_t swept = sweep_drafts(db);
  const int64_t stalled = sweep_stalled(db);
  json_object *result = sweep_reminders(db);
  json_object_object_add(result, "draftsSwept", json_object_new_int64(swept));
  json_object_object_add(result, "stalledEnrichments", json_object_new_int64(stalled));
  shell_ipc(IPC_TARGET, "refresh", NULL);
  emit(result);
  return 0;
}

int cmd_discard(int argc, char **argv) {
  g_autofree char *id = NULL;
  const GOptionEntry entries[] = { { "id", 0, 0, G_OPTION_ARG_STRING, &id, "the draft", "ID" },
    G_OPTION_ENTRY_NULL };
  parse_options("discard", entries, 0, &argc, &argv);
  require_option("discard", "--id", id);
  sqlite3 *db = db_open(true);
  const bool removed = discard(db, id, true);
  shell_ipc(IPC_TARGET, "refresh", NULL);
  json_object *out = json_object_new_object();
  json_object_object_add(out, "discarded", json_object_new_boolean(removed));
  emit(out);
  return removed ? 0 : 2;
}
