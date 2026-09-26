#include "omoide.h"

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void die(int code, const char *fmt, ...) {
  va_list args;
  va_start(args, fmt);
  fputs("omoide: ", stderr);
  vfprintf(stderr, fmt, args);
  fputc('\n', stderr);
  va_end(args);
  exit(code);
}

// OMOIDE_NOW pins the clock for the parity harness, which runs the Python CLI
// with the same value so both sides compute the same "now". Anything that is
// not a full timestamp with a zone is ignored rather than guessed at.
GDateTime *now_utc(void) {
  const char *pinned = g_getenv("OMOIDE_NOW");
  if (pinned && *pinned) {
    GDateTime *dt = g_date_time_new_from_iso8601(pinned, NULL);
    if (dt) {
      GDateTime *utc = g_date_time_to_utc(dt);
      g_date_time_unref(dt);
      return utc;
    }
  }
  return g_date_time_new_now_utc();
}

// UTC, second precision, always with a Z. Every stored timestamp uses this.
char *iso(GDateTime *dt) {
  g_autoptr(GDateTime) utc = g_date_time_to_utc(dt);
  return g_date_time_format(utc, "%Y-%m-%dT%H:%M:%SZ");
}

char *iso_now(void) {
  g_autoptr(GDateTime) dt = now_utc();
  return iso(dt);
}

// A stored timestamp always carries its zone: iso() writes UTC with a Z. A
// value arriving without one came from a person -- typed into the date fields,
// or passed on the command line -- and a person means local time.
//
// GLib only reads full date-times, while people (and the stored data this CLI
// inherited) also write a bare date, "10", or "10:00", with a space or a T. The
// missing parts are filled in and GLib does the actual reading.
GDateTime *parse_iso(const char *value) {
  if (!value || strlen(value) < 10)
    return NULL;
  g_autoptr(GString) text = g_string_new(value);
  if (text->len == 10) {
    g_string_append(text, "T00:00:00");
  } else {
    if (text->str[10] != 'T' && text->str[10] != 't' && text->str[10] != ' ')
      return NULL;
    text->str[10] = 'T';
    // The clock ends where a zone begins, if one does.
    size_t end = 11;
    while (end < text->len && strchr("Zz+-", text->str[end]) == NULL)
      end++;
    int colons = 0;
    for (size_t i = 11; i < end; i++)
      colons += text->str[i] == ':';
    if (colons == 0)
      g_string_insert(text, end, ":00:00");
    else if (colons == 1)
      g_string_insert(text, end, ":00");
  }
  g_autoptr(GTimeZone) local = g_time_zone_new_local();
  return g_date_time_new_from_iso8601(text->str, local);
}

bool has(const char *program) {
  g_autofree char *found = g_find_program_in_path(program);
  return found != NULL;
}

// By character, not byte: a cut through a multibyte sequence is invalid
// UTF-8, and json-c refuses to print it.
char *truncate_chars(const char *text, long limit) {
  if (limit < 0)
    limit = 0;
  if (g_utf8_strlen(text, -1) > limit)
    return g_utf8_substring(text, 0, limit);
  return g_strdup(text);
}

// GLib's own strip only knows ASCII whitespace; text from a model or a
// clipboard can start with a no-break space as easily as a newline.
char *strip_space(const char *text) {
  return re_replace("^\\s+|\\s+$", text ? text : "", "");
}

char *one_line(const char *text, long limit) {
  g_autofree char *clean = re_replace("[\\x{00}-\\x{08}\\x{0b}-\\x{1f}\\x{7f}-\\x{9f}]",
                                      text ? text : "", "");
  g_autofree char *flat = re_replace("\\s+", clean, " ");
  g_strstrip(flat);
  return truncate_chars(flat, limit);
}

char *first_line(const char *text) {
  g_auto(GStrv) lines = g_regex_split(re("\\R", 0), text ? text : "", 0);
  return g_strdup(lines[0] ? lines[0] : "");
}

// Sortable and filesystem-safe: a timestamp plus enough entropy. 12 hex, not
// 6: the stamp has one-second resolution, so the entropy is all that separates
// two ids made in the same second, and at 6 a capture that produced a few
// thousand rows hit UNIQUE about a third of the time.
//
// OMOIDE_TEST_IDS swaps the entropy for a counter, so the parity harness can
// compare two runs that created rows in the same order.
char *new_id(const char *prefix) {
  g_autoptr(GDateTime) now = now_utc();
  g_autofree char *stamp = g_date_time_format(now, "%Y%m%dT%H%M%S");
  char hex[13];
  if (g_getenv("OMOIDE_TEST_IDS")) {
    static unsigned long counter = 0;
    snprintf(hex, sizeof hex, "%012lx", ++counter);
  } else {
    g_autofree char *uuid = g_uuid_string_random();   // 8-4-4-4-12
    memcpy(hex, uuid, 8);
    memcpy(hex + 8, uuid + 9, 4);
    hex[12] = '\0';
  }
  return g_strdup_printf("%s%s-%s", prefix ? prefix : "", stamp, hex);
}

// The shortest spelling that reads back as the same double, with a ".0" on a
// whole number -- what Python prints, and so what the log has always said.
char *py_float(double value) {
  char text[40];
  for (int precision = 1; precision <= 17; precision++) {
    snprintf(text, sizeof text, "%.*g", precision, value);
    if (g_ascii_strtod(text, NULL) == value)
      break;
  }
  if (!strpbrk(text, ".eni"))
    g_strlcat(text, ".0", sizeof text);
  return g_strdup(text);
}

bool truthy(json_object *value) {
  switch (json_object_get_type(value)) {
    case json_type_null: return false;
    case json_type_boolean: return json_object_get_boolean(value);
    case json_type_int: return json_object_get_int64(value) != 0;
    case json_type_double: return json_object_get_double(value) != 0;
    case json_type_string: return json_object_get_string_len(value) > 0;
    case json_type_array: return json_object_array_length(value) > 0;
    case json_type_object: return json_object_object_length(value) > 0;
  }
  return false;
}

char *as_text(json_object *value) {
  switch (json_object_get_type(value)) {
    case json_type_null: return g_strdup("");
    case json_type_string: return g_strdup(json_object_get_string(value));
    case json_type_boolean: return g_strdup(json_object_get_boolean(value) ? "True" : "False");
    case json_type_double: return py_float(json_object_get_double(value));
    default: return g_strdup(json_object_to_json_string_ext(value, JSON_C_TO_STRING_PLAIN));
  }
}

bool as_int(json_object *value, int64_t *out) {
  switch (json_object_get_type(value)) {
    case json_type_boolean:
    case json_type_int:
      *out = json_object_get_int64(value);
      return true;
    case json_type_double: {
      const double d = json_object_get_double(value);
      if (d != d || d > 9e18 || d < -9e18)
        return false;
      *out = (int64_t)d;   // toward zero, as int() does
      return true;
    }
    case json_type_string: {
      g_autofree char *text = g_strstrip(g_strdup(json_object_get_string(value)));
      if (*text == '+')
        memmove(text, text + 1, strlen(text));
      return g_ascii_string_to_signed(text, 10, INT64_MIN, INT64_MAX, out, NULL);
    }
    default:
      return false;
  }
}

// --- the bar widget's settings
//
// Injected into the widget by the shell from its entry in shell.json, and read
// here directly. Never assume a key is present: shell.json is user-owned and
// Omarchy does not merge defaults back in, so a new setting simply appears
// absent on an existing install.
json_object *settings(void) {
  json_object *merged = json_object_new_object();
  json_object_object_add(merged, "defaultAction", json_object_new_string("screenshot"));
  json_object_object_add(merged, "captureMode", json_object_new_string("smart"));

  const char *override = g_getenv("OMOIDE_SHELL_JSON");
  g_autofree char *path = override && *override ? g_strdup(override)
    : g_build_filename(g_get_home_dir(), ".config/omarchy/shell.json", NULL);
  g_autoptr(json_object) config = json_object_from_file(path);

  // Placed in the bar, the widget's entry lives in its section; otherwise in
  // plugins[]. The last section holding it wins, as it always has.
  json_object *entry = NULL;
  json_object *layout = json_get(json_get(config, "bar"), "layout");
  const char *sections[] = { "left", "center", "right" };
  for (size_t s = 0; s < G_N_ELEMENTS(sections); s++) {
    json_object *list = json_get(layout, sections[s]);
    for (size_t i = 0; json_object_is_type(list, json_type_array)
                       && i < json_object_array_length(list); i++) {
      json_object *candidate = json_object_array_get_idx(list, i);
      if (g_strcmp0(json_get_str(candidate, "id"), PLUGIN_ID) == 0) {
        entry = candidate;
        break;
      }
    }
  }
  if (!entry) {
    json_object *plugins = json_get(config, "plugins");
    for (size_t i = 0; json_object_is_type(plugins, json_type_array)
                       && i < json_object_array_length(plugins); i++) {
      json_object *candidate = json_object_array_get_idx(plugins, i);
      if (g_strcmp0(json_get_str(candidate, "id"), PLUGIN_ID) == 0)
        entry = candidate;
    }
  }
  if (!entry)
    return merged;

  json_object_object_foreach(entry, key, value) {
    if (g_str_equal(key, "id"))
      continue;
    json_object *existing = json_get(merged, key);
    if (json_object_is_type(value, json_type_object)
        && json_object_is_type(existing, json_type_object)) {
      json_object_object_foreach(value, inner, inner_value)
        json_object_object_add(existing, inner, json_object_get(inner_value));
    } else {
      json_object_object_add(merged, key, json_object_get(value));
    }
  }
  return merged;
}

// The version a user sees in the plugin list, read from the manifest compiled
// into this binary, so the two can never disagree.
static const char manifest_json[] = {
#embed "../../manifest.json"
  , 0
};

const char *plugin_version(void) {
  static char *version = NULL;
  if (!version) {
    g_autoptr(json_object) manifest = json_tokener_parse(manifest_json);
    json_object *field = NULL;
    const char *value = manifest && json_object_object_get_ex(manifest, "version", &field)
      ? json_object_get_string(field) : NULL;
    version = g_strdup(value ? value : "unknown");
  }
  return version;
}
