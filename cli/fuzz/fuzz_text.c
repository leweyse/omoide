// libFuzzer target for the text this CLI trusts least.
//
// An agent's reply is whatever a model wrote after reading someone else's
// screen, and a note is whatever was typed or dictated. Both reach JSON
// extraction, block validation, the date grammar and the flattening done for
// logs and toasts. Built by dev/fuzz, never shipped.
//
// enrich.c is included rather than linked so its static helpers -- the
// extractor and the validator -- are reachable from here.
#include "../src/enrich.c"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  // What proc.c hands over: another program's output, repaired to UTF-8.
  g_autofree char *text = g_utf8_make_valid((const char *)data, (gssize)size);

  json_object *reply = extract_json(text);
  json_object_put(validate_blocks(json_get(reply, "blocks")));
  json_object_put(reply);

  g_autoptr(GDateTime) when = parse_when(text);
  g_autoptr(GDateTime) stamp = parse_iso(text);
  json_object_put(todo_from_note(text));
  g_free(one_line(text, 300));
  g_free(notify_text(text, 200));
  return 0;
}
