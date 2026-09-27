// Capturing: the screenshot picker, drafts, and turning a draft into a memory.
#include "omoide.h"

#include <errno.h>
#include <fcntl.h>
#include <gio/gio.h>
#include <glib/gstdio.h>
#include <math.h>
#include <signal.h>
#include <string.h>
#include <sys/file.h>
#include <unistd.h>

// --- screenshot
//
// Our own picker rather than omarchy-capture-screenshot. That helper freezes
// the screen with hyprpicker and relies on its own EXIT trap to unfreeze; run
// as a tracked child of the shell, anything that tears the child down, a
// plugin reload above all, skips the trap and leaves the freeze up, which
// presents as a completely locked desktop. Owning the freeze here means it is
// always taken down, and a stale one from a previous run is reaped before the
// next capture starts.

static char *state_file(const char *name) {
  return g_build_filename(paths()->state_dir, name, NULL);
}

// Exclusive for the duration of a capture, or -1 when one is already running.
// The QML side cannot serialise this: the picker is launched detached, so a
// double-click on the bar icon arrives as two captures ~200ms apart, and two
// pickers fight over the pointer while the second reaps the first one's
// freeze. The lock makes the second press a no-op instead.
static int capture_lock(void) {
  g_mkdir_with_parents(paths()->state_dir, 0777);
  g_autofree char *path = state_file("capture.lock");
  const int fd = open(path, O_WRONLY | O_CREAT | O_CLOEXEC, 0666);
  if (fd < 0)
    return -1;
  if (flock(fd, LOCK_EX | LOCK_NB) != 0) {
    close(fd);
    return -1;
  }
  g_autofree char *pid = g_strdup_printf("%d", getpid());
  if (ftruncate(fd, 0) == 0 && write(fd, pid, strlen(pid)) < 0) {
    // The pid is for a person reading the file; the lock is what counts.
  }
  return fd;
}

static char *hypr(const char *a, const char *b, const char *c) {
  const char *argv[] = { "hyprctl", a, b, c, NULL };
  g_auto(ProcResult) run = proc_run(argv, NULL, 0);
  return run.status == 0 ? g_steal_pointer(&run.out) : g_strdup("");
}

static json_object *hypr_json(const char *what) {
  g_autofree char *text = hypr(what, "-j", NULL);
  return json_tokener_parse(text);
}

// Recover from a freeze a previous run failed to clean up.
static void reap_stale_freeze(void) {
  g_autofree char *path = state_file("freeze.pid");
  g_autofree char *text = NULL;
  if (!g_file_get_contents(path, &text, NULL, NULL))
    return;
  char *end = NULL;
  const gint64 pid = g_ascii_strtoll(g_strstrip(text), &end, 10);
  if (end != text && !*end && pid > 0)
    kill((pid_t)pid, SIGTERM);
  g_unlink(path);
}

// Freeze the screen so menus and hover states can be captured.
static GSubprocess *start_freeze(void) {
  if (!has("hyprpicker"))
    return NULL;
  const char *argv[] = { "hyprpicker", "-r", "-z", NULL };
  GSubprocess *freeze = proc_spawn_quiet(argv);
  if (!freeze)
    return NULL;
  g_mkdir_with_parents(paths()->state_dir, 0777);
  g_autofree char *path = state_file("freeze.pid");
  g_file_set_contents(path, g_subprocess_get_identifier(freeze), -1, NULL);
  return freeze;
}

// Block until the freeze surface is actually mapped. A fixed sleep is a race:
// on a cold start hyprpicker needs longer than any delay short enough to feel
// instant, and if slurp maps first it gets no grab and exits at once, so the
// region picker intermittently fails to start.
static bool wait_for_freeze(double timeout_s) {
  const gint64 until = g_get_monotonic_time() + (gint64)(timeout_s * G_TIME_SPAN_SECOND);
  while (g_get_monotonic_time() < until) {
    g_autofree char *layers = hypr("layers", "-j", NULL);
    if (strstr(layers, "\"namespace\": \"hyprpicker\""))
      return true;
    g_usleep(30000);
  }
  return false;
}

static void stop_freeze(GSubprocess *freeze) {
  proc_stop(freeze, 2);
  g_autofree char *path = state_file("freeze.pid");
  g_unlink(path);
}

static bool active_workspace(int64_t *id) {
  g_autoptr(json_object) monitors = hypr_json("monitors");
  for (size_t i = 0; json_object_is_type(monitors, json_type_array) && i < json_object_array_length(monitors);
      i++) {
    json_object *monitor = json_object_array_get_idx(monitors, i);
    if (truthy(json_get(monitor, "focused")))
      return as_int(json_get(json_get(monitor, "activeWorkspace"), "id"), id);
  }
  return false;
}

static int64_t int_of(json_object *value, int64_t fallback) {
  int64_t n;
  return as_int(value, &n) ? n : fallback;
}

// Visible window rectangles, in slurp's format. slurp highlights the smallest
// box containing the pointer and keeps the first on a tie, so a floating
// window resolves over the tiled one beneath. Restricted to the focused
// workspace, and deduplicated: windows stacked at identical geometry collapse
// to one rectangle slurp cannot tell apart.
static void window_boxes(GPtrArray *boxes) {
  int64_t workspace = 0;
  const bool known = active_workspace(&workspace);
  g_autoptr(json_object) clients = hypr_json("clients");
  for (size_t i = 0; json_object_is_type(clients, json_type_array) && i < json_object_array_length(clients);
      i++) {
    json_object *client = json_object_array_get_idx(clients, i);
    if (truthy(json_get(client, "hidden")) || !truthy(json_get(client, "mapped")))
      continue;
    if (known && int_of(json_get(json_get(client, "workspace"), "id"), INT64_MIN) != workspace)
      continue;
    json_object *at = json_get(client, "at"), *size = json_get(client, "size");
    if (json_object_array_length(at) != 2 || json_object_array_length(size) != 2)
      continue;
    const int64_t w = int_of(json_object_array_get_idx(size, 0), 0);
    const int64_t h = int_of(json_object_array_get_idx(size, 1), 0);
    if (w <= 0 || h <= 0)
      continue;
    char *box =
        g_strdup_printf("%" G_GINT64_FORMAT ",%" G_GINT64_FORMAT " %" G_GINT64_FORMAT "x%" G_GINT64_FORMAT,
            int_of(json_object_array_get_idx(at, 0), 0), int_of(json_object_array_get_idx(at, 1), 0), w, h);
    bool seen = false;
    for (size_t b = 0; b < boxes->len && !seen; b++)
      seen = g_str_equal(g_ptr_array_index(boxes, b), box);
    if (seen)
      g_free(box);
    else
      g_ptr_array_add(boxes, box);
  }
}

static double number_of(json_object *value, double fallback) {
  return value && !json_object_is_type(value, json_type_null) ? json_object_get_double(value) : fallback;
}

// Rounded half to even.
static int64_t logical(json_object *monitor, const char *key) {
  const double scale = truthy(json_get(monitor, "scale")) ? number_of(json_get(monitor, "scale"), 1) : 1;
  return (int64_t)nearbyint(number_of(json_get(monitor, key), 0) / scale);
}

// Monitors showing the focused workspace, as slurp rectangles.
static void monitor_boxes(GPtrArray *boxes) {
  int64_t workspace = 0;
  const bool known = active_workspace(&workspace);
  g_autoptr(json_object) monitors = hypr_json("monitors");
  for (size_t i = 0; json_object_is_type(monitors, json_type_array) && i < json_object_array_length(monitors);
      i++) {
    json_object *monitor = json_object_array_get_idx(monitors, i);
    if (known && int_of(json_get(json_get(monitor, "activeWorkspace"), "id"), INT64_MIN) != workspace)
      continue;
    int64_t width = logical(monitor, "width"), height = logical(monitor, "height");
    const int64_t transform = int_of(json_get(monitor, "transform"), 0);
    if (transform == 1 || transform == 3 || transform == 5 || transform == 7) {
      const int64_t swap = width;
      width = height;
      height = swap;
    }
    if (width > 0 && height > 0)
      g_ptr_array_add(boxes,
          g_strdup_printf("%" G_GINT64_FORMAT ",%" G_GINT64_FORMAT " %" G_GINT64_FORMAT "x%" G_GINT64_FORMAT,
              int_of(json_get(monitor, "x"), 0), int_of(json_get(monitor, "y"), 0), width, height));
  }
}

static char *focused_monitor_geometry(void) {
  g_autoptr(json_object) monitors = hypr_json("monitors");
  for (size_t i = 0; json_object_is_type(monitors, json_type_array) && i < json_object_array_length(monitors);
      i++) {
    json_object *monitor = json_object_array_get_idx(monitors, i);
    if (truthy(json_get(monitor, "focused")))
      return g_strdup_printf("%" G_GINT64_FORMAT ",%" G_GINT64_FORMAT " %" G_GINT64_FORMAT
                             "x%" G_GINT64_FORMAT,
          int_of(json_get(monitor, "x"), 0), int_of(json_get(monitor, "y"), 0), logical(monitor, "width"),
          logical(monitor, "height"));
  }
  return NULL;
}

// Geometry for the capture, or NULL when the user cancelled.
static char *pick_region(const char *mode) {
  if (g_str_equal(mode, "fullscreen"))
    return focused_monitor_geometry();

  // Monitors first, then windows: slurp keeps the first box on a tie, so a
  // window has to come later to win over the monitor behind it. slurp ALWAYS
  // gets rectangles, and this is load-bearing: it treats EOF with none as an
  // immediate cancel, exiting before the user can drag anything.
  g_autoptr(GPtrArray) boxes = g_ptr_array_new_with_free_func(g_free);
  monitor_boxes(boxes);
  window_boxes(boxes);
  if (boxes->len == 0)
    return NULL;
  g_ptr_array_add(boxes, NULL);
  g_autofree char *joined = g_strjoinv("\n", (char **)boxes->pdata);
  g_autofree char *input = g_strconcat(joined, "\n", NULL);

  const bool window = g_str_equal(mode, "window");
  const char *argv[] = { "slurp", "-w", "2", window ? "-r" : NULL, NULL };   // -r: whole windows
  g_auto(ProcResult) picked = proc_run(argv, input, 0);
  if (picked.status != 0)
    return NULL;   // cancelled with Esc or right-click
  g_strstrip(picked.out);
  return *picked.out ? g_steal_pointer(&picked.out) : NULL;
}

static char *take_screenshot(const char *mode, const char *target, bool freeze) {
  if (!has("grim"))
    die(1, "grim is not installed");
  // Checked before anything is frozen: a die() further in would leave the
  // screen frozen behind it.
  if (!g_str_equal(mode, "fullscreen") && !has("slurp"))
    die(1, "slurp is not installed");

  const int lock = capture_lock();
  if (lock < 0)
    return NULL;   // a picker is already open; leave it alone
  reap_stale_freeze();

  // Software cursors so the pointer appears in the grab, restored afterwards.
  g_autofree char *cursor = NULL;
  GSubprocess *frozen = NULL;
  if (freeze && !g_str_equal(mode, "fullscreen")) {
    cursor = hypr("getoption", "cursor:no_hardware_cursors", "-j");
    frozen = start_freeze();
    if (frozen) {
      g_autofree char *set = hypr("keyword", "cursor:no_hardware_cursors", "0");
      wait_for_freeze(2.0);
    }
  }

  char *result = NULL;
  g_autofree char *geometry = pick_region(mode);
  if (geometry) {
    g_autofree char *folder = g_path_get_dirname(target);
    g_mkdir_with_parents(folder, 0777);
    const char *argv[] = { "grim", "-g", geometry, target, NULL };
    g_auto(ProcResult) grab = proc_run(argv, NULL, 0);
    if (grab.status == 0 && g_file_test(target, G_FILE_TEST_EXISTS))
      result = g_strdup(target);
  }

  // The whole point: a freeze we started is always taken down.
  stop_freeze(frozen);
  close(lock);
  if (cursor && *cursor) {
    g_autoptr(json_object) option = json_tokener_parse(cursor);
    json_object *previous = json_get(option, "int");
    if (previous && !json_object_is_type(previous, json_type_null)) {
      g_autofree char *value = as_text(previous);
      g_autofree char *restored = hypr("keyword", "cursor:no_hardware_cursors", value);
    }
  }
  return result;
}

static char *ocr(const char *image) {
  if (!has("tesseract"))
    return g_strdup("");
  const char *langs = g_getenv("OMARCHY_OCR_LANGS");
  const char *argv[] = { "tesseract", image, "stdout", "--oem", "1", "--psm", "6", "-l",
    langs ? langs : "eng", "--dpi", "300", "-c", "preserve_interword_spaces=1", NULL };
  g_auto(ProcResult) run = proc_run(argv, NULL, 60);
  if (run.status != 0)
    return g_strdup("");
  return strip_space(run.out);
}

// Pre-generated thumbnails: scaling full PNGs makes the grid stutter.
static char *make_thumb(const char *image) {
  if (!has("ffmpeg"))
    return NULL;
  g_autofree char *folder = g_path_get_dirname(image);
  char *thumb = g_build_filename(folder, "thumb.png", NULL);
  const char *argv[] = { "ffmpeg", "-y", "-loglevel", "error", "-i", image, "-vf",
    "scale=640:-1:flags=lanczos", thumb, NULL };
  g_auto(ProcResult) run = proc_run(argv, NULL, 30);
  if (run.status == 0 && g_file_test(thumb, G_FILE_TEST_EXISTS))
    return thumb;
  g_free(thumb);
  return NULL;
}

// Relative to the data dir, as every stored path is.
static const char *relative_to_data(const char *path) {
  const char *data = paths()->data_dir;
  const size_t n = strlen(data);
  return strncmp(path, data, n) == 0 && path[n] == '/' ? path + n + 1 : path;
}

static char *attach_image(sqlite3 *db, const char *memory_id, const char *source) {
  g_autofree char *folder = blob_dir_of(memory_id);
  if (!folder)
    die(1, "not a memory id: %s", memory_id);
  g_mkdir_with_parents(folder, 0777);
  char *target = g_build_filename(folder, "capture.png", NULL);
  if (!g_str_equal(source, target)) {
    g_autoptr(GFile) from = g_file_new_for_path(source);
    g_autoptr(GFile) to = g_file_new_for_path(target);
    g_autoptr(GError) error = NULL;
    if (!g_file_move(from, to, G_FILE_COPY_OVERWRITE, NULL, NULL, NULL, &error))
      die(1, "could not store the capture: %s", error->message);
  }
  int64_t width = 0, height = 0;
  const bool measured = image_size(target, &width, &height);
  GStatBuf st = { 0 };
  g_stat(target, &st);
  g_autofree char *id = new_id(NULL);
  g_autofree char *w = measured ? g_strdup_printf("%" G_GINT64_FORMAT, width) : NULL;
  g_autofree char *h = measured ? g_strdup_printf("%" G_GINT64_FORMAT, height) : NULL;
  g_autoptr(sqlite3_stmt) insert = db_query(db,
      "INSERT INTO attachments (id, memory_id, kind, rel_path, mime, bytes, width, height) "
      "VALUES (?,?,'image',?,'image/png',?,CAST(? AS INTEGER),CAST(? AS INTEGER))",
      "sssiss", id, memory_id, relative_to_data(target), (int64_t)st.st_size, w, h);
  db_step(insert);
  return target;
}

static const char *const MODES[] = { "screenshot", "note", "voice", "clipboard", NULL };

int cmd_capture(int argc, char **argv) {
  g_autofree char *mode_option = NULL;
  const GOptionEntry entries[] = {
    { "mode", 0, G_OPTION_FLAG_HIDDEN, G_OPTION_ARG_STRING, &mode_option, NULL, NULL }, G_OPTION_ENTRY_NULL
  };
  parse_options("capture", entries, 1, &argc, &argv);
  // The positional wins over --mode when both are given.
  const char *requested = positional(argc, argv) ? positional(argc, argv) : mode_option;
  if (requested)
    require_choice("capture", "mode", requested, MODES);

  g_autoptr(json_object) config = settings();
  g_autofree char *default_action = as_text(json_get(config, "defaultAction"));
  const char *mode = requested ? requested : *default_action ? default_action : "screenshot";

  if (g_str_equal(mode, "clipboard"))
    die(2, "clipboard capture is not enabled yet");
  if (g_str_equal(mode, "voice") && !has("voxtype")) {
    const char *install[] = { "omarchy-voxtype-install", NULL };
    notify("Dictation is not set up", "Install Voxtype to capture voice notes.", NULL, NULL, install);
    die(2, "voxtype is not installed");
  }

  g_autofree char *memory_id = new_id(NULL);
  g_autofree char *shot = NULL;
  if (g_str_equal(mode, "screenshot")) {
    g_autofree char *capture_mode =
        json_get(config, "captureMode") ? as_text(json_get(config, "captureMode")) : g_strdup("smart");
    json_object *freeze = json_get(config, "captureFreeze");
    const bool freeze_on =
        !(json_object_is_type(freeze, json_type_boolean) && !json_object_get_boolean(freeze));
    g_autofree char *folder = blob_dir_of(memory_id);
    g_autofree char *target = g_build_filename(folder, "capture.png", NULL);
    shot = take_screenshot(capture_mode, target, freeze_on);
    if (!shot)
      return 2;   // cancelled: write nothing at all
  }

  sqlite3 *db = db_open(true);
  g_autofree char *stamp = iso_now();
  g_autoptr(sqlite3_stmt) insert = db_query(db,
      "INSERT INTO memories (id, created_at, updated_at, status, ai_status) "
      "VALUES (?,?,?,'draft','none')",
      "sss", memory_id, stamp, stamp);
  db_step(insert);
  g_autofree char *stored = shot ? attach_image(db, memory_id, shot) : NULL;

  json_object *payload = json_object_new_object();
  json_object_object_add(payload, "id", json_object_new_string(memory_id));
  json_object_object_add(payload, "mode", json_object_new_string(mode));
  json_object_object_add(payload, "hasImage", json_object_new_boolean(stored != NULL));
  json_object_object_add(payload, "image", json_str_or_empty(stored));
  json_object_object_add(payload, "autoDictate", json_object_new_boolean(g_str_equal(mode, "voice")));
  json_object_object_add(payload, "voiceAvailable", json_object_new_boolean(has("voxtype")));

  // The overlay opens only now, so it is never in its own screenshot.
  shell_ipc(IPC_TARGET, "compose", json_object_to_json_string_ext(payload, JSON_C_TO_STRING_PLAIN));
  emit(payload);
  return 0;
}

static char *commit_pidfile(const char *memory_id) {
  g_autofree char *name = g_strdup_printf("commit-%s.pid", memory_id);
  return state_file(name);
}

static int64_t count(sqlite3 *db, const char *sql, const char *memory_id) {
  g_autoptr(sqlite3_stmt) row = db_query(db, sql, "s", memory_id);
  db_step(row);
  return sqlite3_column_int64(row, 0);
}

static void set_memory_text(sqlite3 *db, const char *sql, const char *value, const char *memory_id) {
  g_autoptr(sqlite3_stmt) update = db_query(db, sql, "ss", value, memory_id);
  db_step(update);
}

int cmd_commit(int argc, char **argv) {
  g_autofree char *id = NULL;
  g_autofree char *note_arg = NULL;
  gboolean remove_image = FALSE;
  const GOptionEntry entries[] = { { "id", 0, 0, G_OPTION_ARG_STRING, &id, "the draft", "ID" },
    { "note", 0, 0, G_OPTION_ARG_STRING, &note_arg, "what was typed", "TEXT" },
    { "remove-image", 0, 0, G_OPTION_ARG_NONE, &remove_image, "keep only the note", NULL },
    G_OPTION_ENTRY_NULL };
  parse_options("commit", entries, 0, &argc, &argv);
  require_option("commit", "--id", id);
  sqlite3 *db = db_open(true);

  g_autoptr(sqlite3_stmt) memory = db_query(db, "SELECT * FROM memories WHERE id = ?", "s", id);
  if (!db_step(memory))
    die(1, "no such memory: %s", id);

  g_autofree char *note = strip_space(note_arg ? note_arg : "");
  g_autofree char *image_id = NULL, *image_rel = NULL;
  {
    g_autoptr(sqlite3_stmt) image =
        db_query(db, "SELECT * FROM attachments WHERE memory_id = ? AND kind = 'image'", "s", id);
    if (db_step(image)) {
      image_id = g_strdup(col_str(image, "id"));
      image_rel = g_strdup(col_str(image, "rel_path"));
    }
  }

  if (remove_image && image_id) {
    g_autofree char *folder = blob_dir_of(id);
    if (folder)
      remove_tree(folder);
    g_autoptr(sqlite3_stmt) del = db_query(db, "DELETE FROM attachments WHERE id = ?", "s", image_id);
    db_step(del);
    g_clear_pointer(&image_id, g_free);
    g_clear_pointer(&image_rel, g_free);
  }

  // Defence in depth: the overlay gates on this too, but a memory with no
  // text and no image is worthless and must never be stored.
  if (!*note && !image_id) {
    discard(db, id, true);
    die(2, "nothing to save: a capture needs text, an image, or a voice note");
  }

  g_autoptr(json_object) ai = ai_settings();
  g_auto(GStrv) provider = resolve_provider(ai);
  const bool ai_on = provider != NULL;

  g_autofree char *image_path = image_rel ? data_path(image_rel) : NULL;
  g_autofree char *ocr_text = image_path ? ocr(image_path) : g_strdup("");

  // Capture-owned blocks come first and are never written by the model.
  if (image_id) {
    json_object *payload = json_object_new_object();
    json_object_object_add(payload, "attachment_id", json_object_new_string(image_id));
    json_object_object_add(payload, "caption", json_object_new_string(""));
    g_autofree char *block = add_block(db, id, "image", payload, "capture");
  }
  if (*note) {
    json_object *payload = json_object_new_object();
    json_object_object_add(payload, "text", json_object_new_string(note));
    g_autofree char *block = add_block(db, id, "note", payload, "user");
  }

  g_autofree char *stamp = iso_now();
  g_autoptr(sqlite3_stmt) ready = db_query(db,
      "UPDATE memories SET status = 'ready', ai_status = ?, ocr_text = ?, updated_at = ? "
      "WHERE id = ?",
      "ssss", ai_on ? "pending" : "none", ocr_text, stamp, id);
  db_step(ready);

  if (image_path) {
    g_autofree char *thumb = make_thumb(image_path);
    if (thumb) {
      g_autoptr(sqlite3_stmt) update = db_query(
          db, "UPDATE attachments SET thumb_path = ? WHERE id = ?", "ss", relative_to_data(thumb), image_id);
      db_step(update);
    }
  }

  // The bar icon must show its working state within a frame, so the shell is
  // told before the model runs, not after.
  g_autofree char *pidfile = commit_pidfile(id);
  if (ai_on) {
    g_mkdir_with_parents(paths()->state_dir, 0777);
    g_autofree char *pid = g_strdup_printf("%d", getpid());
    g_file_set_contents(pidfile, pid, -1, NULL);
  }
  write_index(db);
  shell_ipc(IPC_TARGET, "refresh", NULL);

  g_autofree char *ai_error = NULL;
  g_autoptr(json_object) enriched = ai_on ? run_ai(note, ocr_text, image_path, ai, &ai_error) : NULL;

  int64_t created = 0;
  if (enriched) {
    created += apply_enrichment(db, id, enriched);
  } else if (ai_on) {
    g_autofree char *reason = one_line(ai_error, 500);
    set_memory_text(db, "UPDATE memories SET ai_status = 'failed', ai_error = ? WHERE id = ?", reason, id);
  }

  // Deterministic fallback. Runs whenever the model produced no to-do, so an
  // explicit "remind me ..." still works with AI off, failed, or just quiet.
  if (!created) {
    g_autoptr(json_object) spec = todo_from_note(note);
    if (spec) {
      g_autofree char *block_id =
          add_block(db, id, "todos", json_tokener_parse("{\"item_ids\": []}"), "user");
      g_autofree char *item_id = create_item(db, id, block_id, spec, "manual");
      json_object *payload = json_object_new_object();
      json_object *ids = json_object_new_array();
      json_object_array_add(ids, json_object_new_string(item_id));
      json_object_object_add(payload, "item_ids", ids);
      set_block_payload(db, block_id, payload);
    }
  }

  {
    g_autoptr(sqlite3_stmt) row = db_query(db, "SELECT title FROM memories WHERE id = ?", "s", id);
    db_step(row);
    const char *title = col_str(row, "title");
    if (!title || !*title) {
      g_autofree char *line = first_line(note);
      g_autofree char *fallback = strip_space(line);
      if (!*fallback) {
        g_autoptr(GDateTime) now = now_utc();
        g_autoptr(GDateTime) local = g_date_time_to_local(now);
        g_free(fallback);
        fallback = g_date_time_format(local, "Screenshot %d %b %H:%M");
      }
      g_autofree char *capped = truncate_chars(fallback, 120);
      set_memory_text(db, "UPDATE memories SET title = ? WHERE id = ?", capped, id);
    }
  }

  g_unlink(pidfile);
  refresh_fts(db, id);
  g_autoptr(json_object) swept = sweep_reminders(db);
  write_index(db);
  shell_ipc(IPC_TARGET, "refresh", NULL);

  g_autoptr(sqlite3_stmt) saved = db_query(db, "SELECT * FROM memories WHERE id = ?", "s", id);
  db_step(saved);
  // Only alarms on ACTIVE items are scheduled, so a cancelled item's reminder
  // must not be counted: it would promise a notification that never comes.
  const int64_t pending = count(db,
      "SELECT COUNT(*) FROM reminders r JOIN items i ON i.id = r.item_id "
      "WHERE i.memory_id = ? AND r.status = 'pending' "
      "AND i.status = 'active'",
      id);
  const int64_t todos = count(db,
      "SELECT COUNT(*) FROM items WHERE memory_id = ? AND kind = 'todo' "
      "AND status = 'active' AND completed_at IS NULL",
      id);
  const int64_t suggested = count(db,
      "SELECT COUNT(*) FROM items WHERE memory_id = ? "
      "AND kind = 'todo' AND status = 'suggested'",
      id);

  const char *ai_status = col_str(saved, "ai_status");
  g_autofree char *body = NULL;
  if (g_strcmp0(ai_status, "failed") == 0)
    body = g_strdup("Enrichment failed — the capture is intact.");
  else if (pending)
    body = g_strdup_printf("%" G_GINT64_FORMAT " reminder%s scheduled", pending, pending != 1 ? "s" : "");
  else if (suggested)
    body = g_strdup_printf(
        "%" G_GINT64_FORMAT " to-do%s suggested — open to add", suggested, suggested != 1 ? "s" : "");
  else if (todos)
    body = g_strdup_printf("%" G_GINT64_FORMAT " to-do%s added", todos, todos != 1 ? "s" : "");
  else
    body = g_strdup(col_str(saved, "title") ? col_str(saved, "title") : "");

  g_auto(GStrv) open = open_space_argv(id, NULL);
  notify("Memory saved", body, NULL, image_path, (const char *const *)open);

  json_object *out = json_object_new_object();
  json_object_object_add(out, "id", json_object_new_string(id));
  json_object_object_add(out, "aiStatus", json_str(ai_status));
  json_object_object_add(out, "reminders", json_object_new_int64(pending));
  json_object_object_add(out, "todos", json_object_new_int64(todos));
  json_object_object_add(out, "suggested", json_object_new_int64(suggested));
  emit(out);
  return 0;
}

// Run the agent again on a capture that already exists. commit cannot be
// reused for this: it would insert a second note and image block. Only the
// agent's own output is replaced, and only rows the user has not corrected.
// An edited block survives a retry, which is what the `edited` flag is for.
int cmd_enrich(int argc, char **argv) {
  g_autofree char *id = NULL;
  const GOptionEntry entries[] = { { "id", 0, 0, G_OPTION_ARG_STRING, &id, "the memory", "ID" },
    G_OPTION_ENTRY_NULL };
  parse_options("enrich", entries, 0, &argc, &argv);
  require_option("enrich", "--id", id);
  sqlite3 *db = db_open(true);

  g_autofree char *ocr_text = NULL;
  {
    g_autoptr(sqlite3_stmt) memory = db_query(db, "SELECT * FROM memories WHERE id = ?", "s", id);
    if (!db_step(memory))
      die(1, "no such memory: %s", id);
    ocr_text = g_strdup(col_str(memory, "ocr_text") ? col_str(memory, "ocr_text") : "");
  }

  g_autoptr(json_object) ai = ai_settings();
  g_auto(GStrv) provider = resolve_provider(ai);
  if (!provider)
    die(2, "no agent is configured; run `omoide setup-ai` first");

  g_autofree char *note = NULL;
  {
    g_autoptr(sqlite3_stmt) row = db_query(db,
        "SELECT payload FROM blocks WHERE memory_id = ? AND type = 'note' "
        "ORDER BY position LIMIT 1",
        "s", id);
    g_autoptr(json_object) payload = db_step(row) ? json_tokener_parse(col_str(row, "payload")) : NULL;
    const char *text = json_get_str(payload, "text");
    note = g_strdup(text ? text : "");
  }
  g_autofree char *image_path = NULL;
  {
    g_autoptr(sqlite3_stmt) image = db_query(db,
        "SELECT rel_path FROM attachments WHERE memory_id = ? AND kind = 'image' "
        "ORDER BY rowid LIMIT 1",
        "s", id);
    if (db_step(image))
      image_path = data_path(col_str(image, "rel_path"));
  }

  // Out with the previous answer. An edited block stays, and so does what the
  // capture owns: the note and the image are never origin 'ai'.
  g_autoptr(GPtrArray) stale = g_ptr_array_new_with_free_func(g_free);
  {
    g_autoptr(sqlite3_stmt) rows =
        db_query(db, "SELECT id FROM blocks WHERE memory_id = ? AND origin = 'ai' AND edited = 0", "s", id);
    while (db_step(rows))
      g_ptr_array_add(stale, g_strdup(col_str(rows, "id")));
  }
  for (size_t i = 0; i < stale->len; i++) {
    const char *block = g_ptr_array_index(stale, i);
    g_autoptr(sqlite3_stmt) items = db_query(db, "DELETE FROM items WHERE block_id = ?", "s", block);
    db_step(items);
    g_autoptr(sqlite3_stmt) del = db_query(db, "DELETE FROM blocks WHERE id = ?", "s", block);
    db_step(del);
  }
  renumber_blocks(db, id);

  g_autoptr(sqlite3_stmt) pending =
      db_query(db, "UPDATE memories SET ai_status = 'pending', ai_error = NULL WHERE id = ?", "s", id);
  db_step(pending);
  write_index(db);
  shell_ipc(IPC_TARGET, "refresh", NULL);

  g_autofree char *reason = NULL;
  g_autoptr(json_object) enriched = run_ai(note, ocr_text, image_path, ai, &reason);
  g_autofree char *short_reason = enriched ? g_strdup("") : one_line(reason, 200);
  if (enriched) {
    apply_enrichment(db, id, enriched);
  } else {
    g_autofree char *stored = one_line(reason, 500);
    set_memory_text(db, "UPDATE memories SET ai_status = 'failed', ai_error = ? WHERE id = ?", stored, id);
  }
  g_autoptr(json_object) swept = sweep_reminders(db);
  refresh_fts(db, id);
  write_index(db);
  shell_ipc(IPC_TARGET, "refresh", NULL);

  json_object *out = json_object_new_object();
  json_object_object_add(out, "id", json_object_new_string(id));
  json_object_object_add(out, "aiStatus", json_object_new_string(enriched ? "ok" : "failed"));
  json_object_object_add(out, "error", json_object_new_string(short_reason));
  emit(out);
  return 0;
}
