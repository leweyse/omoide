// A deterministic date grammar: the fallback when AI is off or fails.
//
// Deliberately small and predictable: it is better to miss a date than to
// invent one, because a wrong date becomes a real notification at a real time.
//
// Calendar steps ("tomorrow", "in 2 days", "friday") keep the wall-clock time
// and take the offset of the day they land on, so "tomorrow at 9" is 9 o'clock
// across a DST change. Python kept the offset of the moment the text was read,
// which put such a reminder an hour out.
#include "omoide.h"

static const struct {
  const char *name;
  char unit;
} UNITS[] = {
  { "min", 'm' },
  { "mins", 'm' },
  { "minute", 'm' },
  { "minutes", 'm' },
  { "m", 'm' },
  { "h", 'h' },
  { "hr", 'h' },
  { "hrs", 'h' },
  { "hour", 'h' },
  { "hours", 'h' },
  { "d", 'd' },
  { "day", 'd' },
  { "days", 'd' },
  { "w", 'w' },
  { "week", 'w' },
  { "weeks", 'w' },
};

// Searched in this order, and the first name found anywhere in the text wins.
static const struct {
  const char *name;
  int weekday;
} WEEKDAYS[] = {
  { "monday", 1 },
  { "mon", 1 },
  { "tuesday", 2 },
  { "tue", 2 },
  { "tues", 2 },
  { "wednesday", 3 },
  { "wed", 3 },
  { "thursday", 4 },
  { "thu", 4 },
  { "thurs", 4 },
  { "friday", 5 },
  { "fri", 5 },
  { "saturday", 6 },
  { "sat", 6 },
  { "sunday", 7 },
  { "sun", 7 },
};

// A matched group as a number. \d matches any Unicode digit, as it did in
// Python, so the digits are read by their Unicode value rather than as ASCII.
static bool group_number(GMatchInfo *match, int group, int *out) {
  g_autofree char *text = g_match_info_fetch(match, group);
  if (!text || !*text)
    return false;
  int value = 0;
  for (const char *p = text; *p; p = g_utf8_next_char(p)) {
    const int digit = g_unichar_digit_value(g_utf8_get_char(p));
    if (digit < 0 || value > 100000)
      return false;
    value = value * 10 + digit;
  }
  *out = value;
  return true;
}

static int group_number_or(GMatchInfo *match, int group, int fallback) {
  int value;
  return group_number(match, group, &value) ? value : fallback;
}

static bool search(const char *pattern, GRegexCompileFlags flags, const char *text, GMatchInfo **match) {
  if (g_regex_match(re(pattern, flags), text, 0, match))
    return true;
  g_clear_pointer(match, g_match_info_free);
  return false;
}

// The same calendar day as `base`, at a given time, in the local zone. NULL
// for a time that does not exist -- 25:00, or a minute of 75.
static GDateTime *at_time(GDateTime *base, int hour, int minute) {
  g_autoptr(GTimeZone) local = g_time_zone_new_local();
  return g_date_time_new(local, g_date_time_get_year(base), g_date_time_get_month(base),
      g_date_time_get_day_of_month(base), hour, minute, 0);
}

static GDateTime *on_date(int year, int month, int day, int hour, int minute) {
  g_autoptr(GTimeZone) local = g_time_zone_new_local();
  return g_date_time_new(local, year, month, day, hour, minute, 0);
}

static bool parse_clock(const char *lowered, int *hour, int *minute) {
  g_autoptr(GMatchInfo) match = NULL;
  if (search("\\b(?:at\\s+)?(\\d{1,2})(?::(\\d{2}))?\\s*(am|pm)\\b", G_REGEX_CASELESS, lowered, &match)) {
    g_autofree char *half = g_match_info_fetch(match, 3);
    *hour = group_number_or(match, 1, 0) % 12 + (g_ascii_strcasecmp(half, "pm") == 0 ? 12 : 0);
    *minute = group_number_or(match, 2, 0);
    return true;
  }
  g_clear_pointer(&match, g_match_info_free);
  if (search("\\b(?:at\\s+)?([01]?\\d|2[0-3]):([0-5]\\d)\\b", 0, lowered, &match)) {
    *hour = group_number_or(match, 1, 0);
    *minute = group_number_or(match, 2, 0);
    return true;
  }
  return false;
}

// Best-effort natural-language date, in local time. NULL rather than a guess.
GDateTime *parse_when(const char *text) {
  if (!text || !*text)
    return NULL;
  g_autoptr(GDateTime) now = now_utc();
  g_autoptr(GDateTime) reference = g_date_time_to_local(now);
  g_autofree char *lowered = g_utf8_strdown(text, -1);
  g_autoptr(GMatchInfo) match = NULL;

  if (search("\\bin\\s+(\\d+)\\s*([a-z]+)\\b", 0, lowered, &match)) {
    g_autofree char *unit = g_match_info_fetch(match, 2);
    int amount = 0;
    for (size_t i = 0; i < G_N_ELEMENTS(UNITS); i++) {
      if (!g_str_equal(unit, UNITS[i].name) || !group_number(match, 1, &amount))
        continue;
      switch (UNITS[i].unit) {
        case 'm': return g_date_time_add_minutes(reference, amount);
        case 'h': return g_date_time_add_hours(reference, amount);
        case 'd': return g_date_time_add_days(reference, amount);
        default: return g_date_time_add_weeks(reference, amount);
      }
    }
  }
  g_clear_pointer(&match, g_match_info_free);

  if (search("\\b(\\d{4})-(\\d{2})-(\\d{2})(?:[ tT](\\d{2}):(\\d{2}))?\\b", 0, text, &match))
    return on_date(group_number_or(match, 1, 0), group_number_or(match, 2, 0), group_number_or(match, 3, 0),
        group_number_or(match, 4, 9), group_number_or(match, 5, 0));
  g_clear_pointer(&match, g_match_info_free);

  // Day-first, matching the editor's fields and the European locale this runs
  // in. Without it "24/08/2026 09:00" fell through to the bare-clock branch and
  // resolved to the next 09:00, ignoring the date entirely.
  if (search("\\b(\\d{1,2})/(\\d{1,2})/(\\d{4})(?:[ ,]+(\\d{1,2}):(\\d{2}))?\\b", 0, text, &match))
    return on_date(group_number_or(match, 3, 0), group_number_or(match, 2, 0), group_number_or(match, 1, 0),
        group_number_or(match, 4, 9), group_number_or(match, 5, 0));
  g_clear_pointer(&match, g_match_info_free);

  int hour = 0, minute = 0;
  bool clock = parse_clock(lowered, &hour, &minute);
  g_autoptr(GDateTime) base = NULL;

  if (search("\\btonight\\b", 0, lowered, &match)) {
    base = g_date_time_ref(reference);
    if (!clock) {
      hour = 20;
      minute = 0;
      clock = true;
    }
  } else if (search("\\btomorrow\\b", 0, lowered, &match)) {
    base = g_date_time_add_days(reference, 1);
  } else if (search("\\btoday\\b", 0, lowered, &match)) {
    base = g_date_time_ref(reference);
  } else {
    for (size_t i = 0; i < G_N_ELEMENTS(WEEKDAYS) && !base; i++) {
      g_autofree char *pattern = g_strdup_printf("\\b%s\\b", WEEKDAYS[i].name);
      if (!search(pattern, 0, lowered, &match))
        continue;
      int ahead = ((WEEKDAYS[i].weekday - g_date_time_get_day_of_week(reference)) % 7 + 7) % 7;
      base = g_date_time_add_days(reference, ahead ? ahead : 7);
    }
  }

  if (!base) {
    // A bare time with no day means the next occurrence of that time.
    if (!clock)
      return NULL;
    GDateTime *candidate = at_time(reference, hour, minute);
    if (!candidate || g_date_time_compare(candidate, reference) > 0)
      return candidate;
    GDateTime *next = g_date_time_add_days(candidate, 1);
    g_date_time_unref(candidate);
    return next;
  }
  return clock ? at_time(base, hour, minute) : at_time(base, 9, 0);
}
