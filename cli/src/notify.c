#include "omoide.h"

#include <string.h>

// Text safe to hand a notification.
//
// The shell's notification card renders its SUMMARY with Qt's default
// AutoText, which sniffs for markup, and markup loads <img src> over the
// network. A to-do's title is written by a model reading someone else's web
// page, so it lands there as untrusted text. Angle brackets are dropped rather
// than escaped, because an escaped entity would just render as "&lt;".
char *notify_text(const char *value, long limit) {
  g_autofree char *stripped = g_strdup(value ? value : "");
  char *write = stripped;
  for (const char *read = stripped; *read; read++)
    if (*read != '<' && *read != '>')
      *write++ = *read;
  *write = '\0';
  return one_line(stripped, limit);
}

static char *notification_binary(void) {
  char *found = g_find_program_in_path("omarchy-notification-send");
  if (found)
    return found;
  const char *omarchy = g_getenv("OMARCHY_PATH");
  char *candidate = g_build_filename(
      omarchy && *omarchy ? omarchy : "/usr/share/omarchy", "bin", "omarchy-notification-send", NULL);
  if (g_file_test(candidate, G_FILE_TEST_IS_EXECUTABLE))
    return candidate;
  g_free(candidate);
  return NULL;
}

// Desktop notification via Omarchy's wrapper, never notify-send directly: the
// wrapper adds the DND-bypass and glyph hints, and --exec is how a toast becomes
// clickable.
//
// --exec comes last and takes the rest of the line as separate words: the
// wrapper treats everything after it as the click command's argv, and rejects
// a single word containing spaces. Passed before the headline as one quoted
// string, a clickable toast fails without a trace.
void notify(const char *headline, const char *body, const char *urgency, const char *image,
    const char *const *exec_argv) {
  g_autofree char *binary = notification_binary();
  if (!binary)
    return;
  g_autoptr(GStrvBuilder) argv = g_strv_builder_new();
  g_strv_builder_add_many(argv, binary, "-g", GLYPH, NULL);
  if (urgency)
    g_strv_builder_add_many(argv, "-u", urgency, NULL);
  if (image)
    g_strv_builder_add_many(argv, "--image", image, NULL);
  g_strv_builder_take(argv, notify_text(headline, 200));
  if (body && *body)
    g_strv_builder_take(argv, notify_text(body, 300));
  if (exec_argv) {
    g_strv_builder_add(argv, "--exec");
    g_strv_builder_addv(argv, (const char **)exec_argv);
  }
  g_auto(GStrv) command = g_strv_builder_end(argv);
  // Fire and forget, as the toast outlives this process anyway.
  g_spawn_async(
      NULL, command, NULL, G_SPAWN_STDOUT_TO_DEV_NULL | G_SPAWN_STDERR_TO_DEV_NULL, NULL, NULL, NULL, NULL);
}

// What a toast runs when clicked: the Space window, opened on this memory.
GStrv open_space_argv(const char *memory_id, const char *section) {
  g_autoptr(json_object) payload = json_object_new_object();
  if (memory_id && *memory_id)
    json_object_object_add(payload, "id", json_object_new_string(memory_id));
  if (section && *section)
    json_object_object_add(payload, "section", json_object_new_string(section));
  const char *text = json_object_to_json_string_ext(payload, JSON_C_TO_STRING_PLAIN);
  return g_strdupv((char *[]){ "omarchy-shell", "-q", IPC_TARGET, "openSpace", (char *)text, NULL });
}

void shell_ipc(const char *target, const char *method, const char *argument) {
  g_autofree char *binary = g_find_program_in_path("omarchy-shell");
  if (!binary)
    return;
  const char *argv[] = { binary, "-q", target, method, argument, NULL };
  g_auto(ProcResult) result = proc_run(argv, NULL, 5);
}
