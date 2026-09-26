#include "omoide.h"

#include <glib/gstdio.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

enum { LOG_MAX_BYTES = 256 * 1024 };   // a few thousand lines; days of ordinary use

// Size-capped rather than truncated per run. The failure worth reading is
// usually the previous one, so keeping the tail preserves several captures'
// worth of history for a quarter of a megabyte.
static void trim(const char *path) {
  GStatBuf st;
  if (g_stat(path, &st) != 0 || st.st_size <= LOG_MAX_BYTES)
    return;
  g_autofree char *contents = NULL;
  gsize length = 0;
  if (!g_file_get_contents(path, &contents, &length, NULL))
    return;
  const char *tail = contents + length - LOG_MAX_BYTES / 2;
  // Drop the partial first line so the file always starts mid-nothing.
  const char *newline = memchr(tail, '\n', contents + length - tail);
  if (newline)
    tail = newline + 1;
  g_autofree char *trimmed = g_strconcat("--- trimmed ---\n", tail, NULL);
  g_file_set_contents(path, trimmed, -1, NULL);
}

// Failures here are swallowed: logging must never take a capture down.
void log_event(const char *event, ...) {
  const Paths *p = paths();
  if (g_mkdir_with_parents(p->state_dir, 0755) != 0)
    return;
  trim(p->log_path);

  g_autoptr(GString) line = g_string_new(NULL);
  g_autofree char *stamp = iso_now();
  g_string_append_printf(line, "%s %s", stamp, event);

  va_list args;
  va_start(args, event);
  const char *key;
  while ((key = va_arg(args, const char *))) {
    const char *value = va_arg(args, const char *);
    g_autofree char *text = g_strdup(value ? value : "");
    g_strdelimit(text, "\n", ' ');
    g_strstrip(text);
    // Quoted only when it has to be, so the common line stays greppable as
    // key=value.
    const bool quote = *text == '\0' || strchr(text, ' ');
    g_string_append_printf(line, quote ? " %s=\"%s\"" : " %s=%s", key, text);
  }
  va_end(args);
  g_string_append_c(line, '\n');

  FILE *handle = g_fopen(p->log_path, "a");
  if (!handle)
    return;
  fputs(line->str, handle);
  fclose(handle);
}
