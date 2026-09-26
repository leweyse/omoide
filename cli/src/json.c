#include "omoide.h"

#include <stdio.h>
#include <string.h>

enum { PLAIN = JSON_C_TO_STRING_PLAIN | JSON_C_TO_STRING_NOSLASHESCAPE };

// Plain, with non-ASCII left as UTF-8 and "/" unescaped: paths and URLs are
// most of what this prints, and the QML side parses it either way.
void emit(json_object *payload) {
  fputs(json_object_to_json_string_ext(payload, PLAIN), stdout);
  fputc('\n', stdout);
  json_object_put(payload);
}

json_object *json_str(const char *value) {
  return value ? json_object_new_string(value) : NULL;
}

json_object *json_str_or_empty(const char *value) {
  return json_object_new_string(value ? value : "");
}

// json-c prints doubles with %.17g, so 16/9 rounded to four places came out as
// 1.7777999999999999. The value is rounded to four places anyway, so four
// places with the trailing zeros taken off is its shortest exact spelling.
json_object *json_round4(double value) {
  char text[64];
  snprintf(text, sizeof text, "%.4f", value);
  char *end = text + strlen(text) - 1;
  while (*end == '0' && end[-1] != '.')
    *end-- = '\0';
  return json_object_new_double_s(g_ascii_strtod(text, NULL), text);
}

// Temp file and rename, so a watcher never sees a half-written file.
bool write_json_file(const char *path, json_object *payload) {
  g_autofree char *text = g_strconcat(
    json_object_to_json_string_ext(payload, JSON_C_TO_STRING_PRETTY
                                   | JSON_C_TO_STRING_NOSLASHESCAPE), "\n", NULL);
  return g_file_set_contents(path, text, -1, NULL);
}

json_object *json_get(json_object *object, const char *key) {
  json_object *value = NULL;
  if (!object || !json_object_is_type(object, json_type_object)
      || !json_object_object_get_ex(object, key, &value))
    return NULL;
  return value;
}

const char *json_get_str(json_object *object, const char *key) {
  json_object *value = json_get(object, key);
  return value && json_object_is_type(value, json_type_string)
    ? json_object_get_string(value) : NULL;
}
