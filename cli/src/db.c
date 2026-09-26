#include "omoide.h"

#include <errno.h>
#include <glib/gstdio.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>

// Compiled in rather than read from sql/migrations at run time, so the binary
// and the schema it expects can never come from two different checkouts.
// A new migration needs a line here as well as its file.
static const char migration_001[] = {
#embed "../../sql/migrations/001-initial.sql"
  , 0
};
static const char migration_002[] = {
#embed "../../sql/migrations/002-drop-reminder-unit.sql"
  , 0
};

static const struct {
  int number;
  const char *sql;
} MIGRATIONS[] = {
  { 1, migration_001 },
  { 2, migration_002 },
};

static_assert(G_N_ELEMENTS(MIGRATIONS) == SCHEMA_VERSION,
              "SCHEMA_VERSION must match the last migration");

static void exec_or_die(sqlite3 *db, const char *sql, const char *what) {
  char *error = NULL;
  if (sqlite3_exec(db, sql, NULL, NULL, &error) != SQLITE_OK)
    die(1, "%s: %s", what, error ? error : sqlite3_errmsg(db));
}

void db_exec(sqlite3 *db, const char *sql) {
  exec_or_die(db, sql, "database error");
}

sqlite3_stmt *db_query(sqlite3 *db, const char *sql, const char *types, ...) {
  sqlite3_stmt *stmt = NULL;
  if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK)
    die(1, "database error: %s\n  in: %s", sqlite3_errmsg(db), sql);
  va_list args;
  va_start(args, types);
  for (int i = 0; types && types[i]; i++) {
    int rc;
    if (types[i] == 's') {
      const char *value = va_arg(args, const char *);
      rc = value ? sqlite3_bind_text(stmt, i + 1, value, -1, SQLITE_TRANSIENT)
                 : sqlite3_bind_null(stmt, i + 1);
    } else {
      rc = sqlite3_bind_int64(stmt, i + 1, va_arg(args, int64_t));
    }
    if (rc != SQLITE_OK)
      die(1, "database error: %s\n  in: %s", sqlite3_errmsg(db), sql);
  }
  va_end(args);
  return stmt;
}

bool db_step(sqlite3_stmt *stmt) {
  const int rc = sqlite3_step(stmt);
  if (rc == SQLITE_ROW)
    return true;
  if (rc != SQLITE_DONE)
    die(1, "database error: %s\n  in: %s", sqlite3_errmsg(sqlite3_db_handle(stmt)),
        sqlite3_sql(stmt));
  return false;
}

// Looked up per call rather than cached: a row has a handful of columns and
// a command reads a few hundred rows at most.
static int column(sqlite3_stmt *stmt, const char *name) {
  const int count = sqlite3_column_count(stmt);
  for (int i = 0; i < count; i++)
    if (strcmp(sqlite3_column_name(stmt, i), name) == 0)
      return i;
  die(1, "no column %s in: %s", name, sqlite3_sql(stmt));   // a bug, not data
}

const char *col_str(sqlite3_stmt *stmt, const char *name) {
  return (const char *)sqlite3_column_text(stmt, column(stmt, name));
}

int64_t col_int(sqlite3_stmt *stmt, const char *name) {
  return sqlite3_column_int64(stmt, column(stmt, name));
}

bool col_null(sqlite3_stmt *stmt, const char *name) {
  return sqlite3_column_type(stmt, column(stmt, name)) == SQLITE_NULL;
}

int db_user_version(sqlite3 *db) {
  sqlite3_stmt *stmt = NULL;
  int version = 0;
  if (sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &stmt, NULL) == SQLITE_OK
      && sqlite3_step(stmt) == SQLITE_ROW)
    version = sqlite3_column_int(stmt, 0);
  sqlite3_finalize(stmt);
  return version;
}

// A snapshot taken before migrating, so a migration that fails part-way has
// something to go back to. VACUUM INTO rather than a file copy: in WAL mode
// the database file alone can be missing committed writes.
static char *backup(sqlite3 *db) {
  g_autofree char *name = g_strdup_printf("memories.db.pre-v%d", SCHEMA_VERSION);
  char *path = g_build_filename(paths()->state_dir, name, NULL);
  g_unlink(path);   // VACUUM INTO refuses to overwrite
  char *sql = sqlite3_mprintf("VACUUM INTO %Q", path);   // SQLite's allocator: sqlite3_free
  exec_or_die(db, sql, "could not back the database up before migrating");
  sqlite3_free(sql);
  return path;
}

static void migrate(sqlite3 *db, int from) {
  g_autofree char *snapshot = from > 0 ? backup(db) : NULL;

  for (size_t i = 0; i < G_N_ELEMENTS(MIGRATIONS); i++) {
    if (MIGRATIONS[i].number <= from)
      continue;
    // One transaction per migration, version bump included, so an
    // interrupted run leaves the schema at a version it actually has.
    g_autofree char *what = g_strdup_printf("migration %03d failed", MIGRATIONS[i].number);
    exec_or_die(db, "BEGIN IMMEDIATE", what);
    char *error = NULL;
    if (sqlite3_exec(db, MIGRATIONS[i].sql, NULL, NULL, &error) != SQLITE_OK) {
      g_autofree char *message = g_strdup(error ? error : sqlite3_errmsg(db));
      sqlite3_free(error);
      sqlite3_exec(db, "ROLLBACK", NULL, NULL, NULL);
      die(1, "%s: %s", what, message);
    }
    g_autofree char *bump = g_strdup_printf("PRAGMA user_version = %d", MIGRATIONS[i].number);
    exec_or_die(db, bump, what);
    exec_or_die(db, "COMMIT", what);
  }

  if (snapshot)
    g_unlink(snapshot);   // clean on success; no litter left behind
}

// One connection per process, closed on the way out however the command ends
// -- a normal return or a die() -- so the WAL is checkpointed and nothing is
// left for a leak checker to report. close_v2 because a die() can leave
// statements unfinalized, and those must not keep the close from happening.
static sqlite3 *open_db = NULL;

static void close_db(void) {
  if (open_db)
    sqlite3_close_v2(open_db);
  open_db = NULL;
}

sqlite3 *db_open(bool write) {
  guard_paths();
  const Paths *p = paths();
  if (g_mkdir_with_parents(p->data_dir, 0777) != 0
      || g_mkdir_with_parents(p->blob_dir, 0777) != 0
      || g_mkdir_with_parents(p->state_dir, 0777) != 0)
    die(1, "could not create %s: %s", p->data_dir, g_strerror(errno));

  // Search is built on FTS5. Arch's SQLite has it; a build without it would
  // only fail later, at the first query that touches the index.
  if (!sqlite3_compileoption_used("ENABLE_FTS5"))
    die(1, "this system's SQLite (%s) was built without FTS5, which Omoide "
           "needs for search", sqlite3_libversion());

  sqlite3 *db = NULL;
  if (sqlite3_open_v2(p->db_path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE,
                      NULL) != SQLITE_OK)
    die(1, "could not open %s: %s", p->db_path, sqlite3_errmsg(db));
  open_db = db;
  atexit(close_db);
  sqlite3_busy_timeout(db, 10000);
  exec_or_die(db, "PRAGMA foreign_keys = ON", "could not configure the database");
  exec_or_die(db, "PRAGMA journal_mode = WAL", "could not configure the database");

  const int version = db_user_version(db);
  if (version > SCHEMA_VERSION) {
    // A rolled-back checkout writing against a schema it does not understand
    // corrupts data silently. Fail loudly instead.
    die(3, "database schema is v%d but this version of the plugin only "
           "understands v%d. Update the plugin, or move %s aside. Refusing to "
           "write.", version, SCHEMA_VERSION, p->db_path);
  }

  if (version < SCHEMA_VERSION && write)
    migrate(db, version);

  return db;
}
