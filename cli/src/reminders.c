#include "omoide.h"

// No system scheduler. The QML service is keepLoaded, so it runs for the whole
// session, and every alarm it could fire needs that session up anyway. So the
// database holds the fire times, index.json publishes the pending ones, and the
// shell arms a single timer against the next.
//
// What the shell must not decide is *whether* an alarm is still owed. That
// stays here, in fire_reminder, so a repeated trigger -- a resumed laptop, two
// shells, a manual run -- costs a no-op instead of a second notification.

// How late an alarm may be and still be worth showing. Past this it retires
// without a toast: a notification for a moment thoroughly gone is noise.
// Inside it -- a reboot, a suspend, a shell restart -- is exactly when the
// reminder is still the thing that was asked for.
static const GTimeSpan LATE_GRACE = 30 * G_TIME_SPAN_MINUTE;

// Deliver one alarm, at most once. Returns what happened:
//   "fired"    the notification went out
//   "expired"  owed, but too late to be useful -- retired without a toast
//   "skipped"  not owed: cancelled, completed, already fired, or still future
//
// The row is marked before the notification is sent rather than after.
// At-most-once is the right guarantee for an alarm: a toast that fails to draw
// is one missed reminder, where a retry loop is a machine that will not stop
// shouting.
const char *fire_reminder(sqlite3 *db, const char *reminder_id) {
  g_autoptr(sqlite3_stmt) row = db_query(
    db, "SELECT r.id, r.fire_at, i.title, i.location, i.memory_id "
        LIVE_REMINDER " AND r.id = ?", "s", reminder_id);
  if (!db_step(row))
    return "skipped";

  g_autoptr(GDateTime) fire_at = parse_iso(col_str(row, "fire_at"));
  g_autoptr(GDateTime) current = now_utc();
  if (!fire_at || g_date_time_compare(fire_at, current) > 0)
    return "skipped";     // armed early; the next tick comes back for it

  g_autoptr(sqlite3_stmt) mark = db_query(
    db, "UPDATE reminders SET status = 'fired' WHERE id = ?", "s", reminder_id);
  db_step(mark);

  const GTimeSpan late = g_date_time_difference(current, fire_at);
  if (late > LATE_GRACE) {
    g_autofree char *minutes = g_strdup_printf("%" G_GINT64_FORMAT, late / G_TIME_SPAN_MINUTE);
    log_event("reminder.expired", "id", reminder_id, "late_min", minutes, NULL);
    return "expired";
  }

  g_autoptr(GDateTime) local = g_date_time_to_local(fire_at);
  g_autofree char *when = g_date_time_format(local, "%H:%M %d %b");
  const char *location = col_str(row, "location");
  g_autofree char *body = location && *location
    ? g_strconcat(when, " · ", location, NULL) : g_strdup(when);
  g_auto(GStrv) open = open_space_argv(col_str(row, "memory_id"), NULL);
  notify(col_str(row, "title"), body, "normal", NULL, (const char *const *)open);
  return "fired";
}

// Catch up on alarms whose moment passed while nothing was watching. Alarms
// are only ever late here, never early: the shell's own timer handles
// everything still in the future.
json_object *sweep_reminders(sqlite3 *db) {
  // Ids first, then fire them one at a time, rather than firing while
  // stepping a cursor over the rows each fire updates.
  g_autoptr(GPtrArray) due = g_ptr_array_new_with_free_func(g_free);
  g_autofree char *now = iso_now();
  {
    g_autoptr(sqlite3_stmt) rows = db_query(
      db, "SELECT r.id " LIVE_REMINDER " AND r.fire_at <= ? ORDER BY r.fire_at", "s", now);
    while (db_step(rows))
      g_ptr_array_add(due, g_strdup(col_str(rows, "id")));
  }

  int64_t fired = 0, expired = 0;
  for (size_t i = 0; i < due->len; i++) {
    const char *outcome = fire_reminder(db, g_ptr_array_index(due, i));
    fired += g_str_equal(outcome, "fired");
    expired += g_str_equal(outcome, "expired");
  }

  g_autoptr(sqlite3_stmt) pending = db_query(db, "SELECT COUNT(*) AS n " LIVE_REMINDER, NULL);
  db_step(pending);
  json_object *result = json_object_new_object();
  json_object_object_add(result, "fired", json_object_new_int64(fired));
  json_object_object_add(result, "expired", json_object_new_int64(expired));
  json_object_object_add(result, "pending", json_object_new_int64(col_int(pending, "n")));
  return result;
}
