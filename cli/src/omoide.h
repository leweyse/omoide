// Omoide helper CLI.
//
// Everything that touches disk lives here: SQLite, blobs, thumbnails, the AI
// enrichment pass, reminder alarms, and the derived index the QML side renders
// from. The QML plugin is deliberately thin: it spawns this and reads JSON
// back.
//
// Exit codes:
//   0  success
//   1  usage or runtime error
//   2  nothing to do (a cancelled capture, an empty submit), and also what a
//      malformed command line exits with
//   3  the database is newer than this code understands; nothing is read or
//      written
#pragma once

#include <glib.h>
#include <json-c/json.h>
#include <sqlite3.h>
#include <stdbool.h>
#include <stdint.h>

#define PLUGIN_ID "leweyse.omoide"
#define IPC_TARGET "omoide"
#define GLYPH "\U000f0a37"   // nf-md-lightbulb_on_outline

enum {
  SCHEMA_VERSION = 2,   // what this code understands
  INDEX_VERSION = 4,   // bump when index.json's shape changes
};

// Stamped in by the build driver in Service.qml; "local" for a hand build.
#ifndef OMOIDE_SRC_ID
#define OMOIDE_SRC_ID "local"
#endif

G_DEFINE_AUTOPTR_CLEANUP_FUNC(json_object, json_object_put)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(json_tokener, json_tokener_free)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(sqlite3_stmt, sqlite3_finalize)

// --- args.c
// Parses a subcommand's options in place, leaving argv[0] and positionals.
// A malformed command line exits 2.
void parse_options(
    const char *command, const GOptionEntry *entries, int max_positional, int *argc, char ***argv);
void require_option(const char *command, const char *flag, const char *value);
void require_choice(const char *command, const char *what, const char *value, const char *const *choices);
const char *positional(int argc, char **argv);

// --- util.c
[[noreturn]] void die(int code, const char *fmt, ...) G_GNUC_PRINTF(2, 3);
GDateTime *now_utc(void);
char *iso(GDateTime *dt);
char *iso_now(void);
GDateTime *parse_iso(const char *value);   // NULL when absent or unreadable
bool has(const char *program);
const char *plugin_version(void);
// Flattened for a log line, an error column or a notification: control
// characters dropped, whitespace runs collapsed, at most `limit` characters.
char *one_line(const char *text, long limit);
char *new_id(const char *prefix);   // sortable and filesystem-safe
char *truncate_chars(const char *text, long limit);   // by character, not byte
char *strip_space(const char *text);   // Unicode whitespace, both ends
char *py_float(double value);   // how Python prints a float: 45.0, 12.5
char *first_line(const char *text);
json_object *settings(void);   // the bar widget's inline settings

// Loose readings of a JSON value that a model or a person may have written as
// any type. Their exact results, down to how a boolean is spelled, reach stored
// rows and the log, and dev/parity pins them.
bool truthy(json_object *value);
char *as_text(json_object *value);   // str(value); "" for NULL
bool as_int(json_object *value, int64_t *out);   // int(value), when it has one

// --- regex.c
// Compiled once per process and cached. Every pattern is UTF-8 with Unicode
// character classes, which is GRegex's default.
GRegex *re(const char *pattern, GRegexCompileFlags flags);
char *re_replace(const char *pattern, const char *text, const char *replacement);

// --- paths.c
typedef struct {
  char *data_dir;
  char *state_dir;
  char *db_path;
  char *blob_dir;
  char *index_path;
  char *config_path;
  char *log_path;
} Paths;

const Paths *paths(void);
void guard_paths(void);

// --- log.c
// Pairs of key and value, ending with NULL. Never pass captured text, an
// agent's output, or a command line the user typed: names and lengths only.
// This is for debugging the plugin, not a second copy of what was captured.
void log_event(const char *event, ...) G_GNUC_NULL_TERMINATED;

// --- json.c
// All machine-readable output goes through here, so stdout stays JSON.
// Takes ownership of `payload`.
void emit(json_object *payload);
json_object *json_str(const char *value);   // NULL becomes JSON null
json_object *json_str_or_empty(const char *value);
json_object *json_round4(double value);   // what Python's round(x, 4) prints
bool write_json_file(const char *path, json_object *payload);   // atomic
json_object *json_get(json_object *object, const char *key);   // NULL if absent
const char *json_get_str(json_object *object, const char *key);   // NULL unless a string

// --- db.c
sqlite3 *db_open(bool write);
int db_user_version(sqlite3 *db);
void db_exec(sqlite3 *db, const char *sql);
// Prepares `sql` and binds one argument per character of `types`:
//   s  const char *   (NULL binds NULL)
//   i  int64_t
// A statement that does not prepare is a bug, so it dies rather than returns.
sqlite3_stmt *db_query(sqlite3 *db, const char *sql, const char *types, ...);
bool db_step(sqlite3_stmt *stmt);   // true while there is a row
// Columns by name. NULL for SQL NULL.
const char *col_str(sqlite3_stmt *stmt, const char *name);
int64_t col_int(sqlite3_stmt *stmt, const char *name);
bool col_null(sqlite3_stmt *stmt, const char *name);
// The live-alarm filter shared by every reader of the scheduler's state.
#define LIVE_REMINDER \
  "FROM reminders r JOIN items i ON i.id = r.item_id " \
  "WHERE r.status = 'pending' AND i.status = 'active' " \
  "AND i.completed_at IS NULL"

// --- proc.c
typedef struct {
  int status;   // exit code, -signal when killed; -1 when it never ran
  bool started;   // false: err says why it could not be run at all
  bool timed_out;
  bool capped;   // proc_run_agent stopped it for printing too much
  char *out;
  char *err;
} ProcResult;

void proc_result_clear(ProcResult *result);
G_DEFINE_AUTO_CLEANUP_CLEAR_FUNC(ProcResult, proc_result_clear)
// argv, never a shell string. `input` goes to stdin when not NULL; 0 means no
// timeout.
ProcResult proc_run(const char *const *argv, const char *input, double timeout_s);
// For an agent: in its own process group, in `cwd`, with `env` added to the
// environment, reading at most `cap` bytes from each stream. A timeout or the
// cap kills the whole group, not just the process we started.
ProcResult proc_run_agent(const char *const *argv, const char *input, double timeout_s, const char *cwd,
    GHashTable *env, size_t cap);
// A helper that runs until stopped (the screen freeze), and stopping it.
typedef struct _GSubprocess GSubprocess;
GSubprocess *proc_spawn_quiet(const char *const *argv);
void proc_stop(GSubprocess *child, double grace_s);

// --- config.c
json_object *ai_settings(void);   // merged over the shipped defaults
GStrv resolve_provider(json_object *ai);   // NULL when AI is off or unusable

// --- notify.c
char *notify_text(const char *value, long limit);
// `exec_argv` makes the toast clickable; NULL for none.
void notify(const char *headline, const char *body, const char *urgency, const char *image,
    const char *const *exec_argv);
GStrv open_space_argv(const char *memory_id, const char *section);
// omarchy-shell -q <target> <method> [argument]. Best-effort: the shell may
// be down.
void shell_ipc(const char *target, const char *method, const char *argument);

// --- index.c
json_object *memory_card(sqlite3 *db, sqlite3_stmt *memory);
json_object *aspect_of(sqlite3_stmt *attachment);
void refresh_fts(sqlite3 *db, const char *memory_id);   // NULL: all of them
void write_index(sqlite3 *db);
int backfill_dimensions(sqlite3 *db);

// --- enrich.c
// A value from a model or a caller as one clean line: as text, whitespace
// collapsed, at most `limit` characters; "" for anything falsy.
char *clean_text(json_object *value, long limit);
char *http_url(json_object *value);   // "" unless http(s)
json_object *todo_from_note(const char *note);   // "remind me to ..." or NULL
// Runs the configured agent. Returns its parsed answer, or NULL with *reason
// saying why not.
json_object *run_ai(
    const char *note, const char *ocr_text, const char *image_path, json_object *ai, char **reason);
int64_t apply_enrichment(sqlite3 *db, const char *memory_id, json_object *enriched);
// The command line each preset runs with, hardening included; `env` gets the
// variables it adds. For the settings dialog as well as for run_ai.
GStrv harden(
    const char *const *argv, const char *provider, bool vision, const char *image_path, GHashTable *env);

// --- dates.c
GDateTime *parse_when(const char *text);   // "tomorrow at 3pm"; NULL, never a guess

// --- items.c
char *add_block(sqlite3 *db, const char *memory_id, const char *type, json_object *payload,
    const char *origin);   // takes `payload`
void set_block_payload(sqlite3 *db, const char *block_id, json_object *payload);
// `spec` is borrowed: kind, title, notes, due_at, starts_at, ends_at, all_day,
// location, map_url, remind, suggested.
char *create_item(
    sqlite3 *db, const char *memory_id, const char *block_id, json_object *spec, const char *source);
void renumber_blocks(sqlite3 *db, const char *memory_id);
void reschedule_item(sqlite3 *db, const char *item_id);
json_object *item_payload(sqlite3 *db, sqlite3_stmt *item);
char *data_path(const char *relative);

// --- reminders.c
const char *fire_reminder(sqlite3 *db, const char *reminder_id);
json_object *sweep_reminders(sqlite3 *db);

// --- memories.c
bool discard(sqlite3 *db, const char *memory_id, bool drafts_only);
void remove_tree(const char *path);   // best-effort; never follows a symlink
char *blob_dir_of(const char *memory_id);   // NULL for an id that is not one component

// --- index.c (media)
bool image_size(const char *path, int64_t *width, int64_t *height);

// --- config.c (presets)
size_t ai_preset_count(void);
const char *ai_preset_name(size_t i);
const char *const *ai_preset_argv(size_t i);
bool is_ai_preset(const char *name);
void write_ai_settings(json_object *ai);   // borrowed; atomic
char *cache_bin_path(void);   // the stable path Service.qml builds the CLI to

// --- commands
int cmd_migrate(int argc, char **argv);
int cmd_state(int argc, char **argv);
int cmd_list(int argc, char **argv);
int cmd_show(int argc, char **argv);
int cmd_search(int argc, char **argv);
int cmd_archive(int argc, char **argv);
int cmd_related(int argc, char **argv);
int cmd_candidates(int argc, char **argv);
int cmd_reindex(int argc, char **argv);
int cmd_sweep(int argc, char **argv);
int cmd_discard(int argc, char **argv);
int cmd_capture(int argc, char **argv);
int cmd_commit(int argc, char **argv);
int cmd_enrich(int argc, char **argv);
int cmd_item(int argc, char **argv);
int cmd_reminder(int argc, char **argv);
int cmd_collection(int argc, char **argv);
int cmd_link(int argc, char **argv);
int cmd_block(int argc, char **argv);
int cmd_delete(int argc, char **argv);
int cmd_memory(int argc, char **argv);
int cmd_keybind(int argc, char **argv);
int cmd_install(int argc, char **argv);
int cmd_uninstall(int argc, char **argv);
int cmd_ai_config(int argc, char **argv);
int cmd_setup_ai(int argc, char **argv);
