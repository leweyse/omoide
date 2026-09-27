---
type: Reference
title: Reminders
description: How an alarm is armed inside the shell from the pulled index and fired, once, by the CLI.
sources:
  - id: service
    resource: ../../../Service.qml
    title: armAlarms and the alarm timer
  - id: reminders
    resource: ../../../cli/src/reminders.c
    title: fire_reminder and sweep_reminders
generated:
  by: anthropic/claude-opus-5-5
  at: '2026-09-26T00:00:00Z'
---

# Reminders

Read this before changing how or when a notification fires. Reminders need nothing outside the shell: no systemd timer, no cron, no daemon.

## The split

- **The shell decides when to ask.** The index the shell pulls lists live alarms by id and time, and nothing else, so no model-written text reaches a timer. `armAlarms()` in `Service.qml` runs on every index change and on its own timer. It fires anything already due and sleeps until the next one, never longer than a fixed tick, which doubles as catch-up after a suspend or a clock jump. It relies on `Service.qml` being kept loaded.
- **The CLI decides whether it is owed.** `reminder fire` marks the row fired before it notifies, so an alarm fires at most once however often the shell asks. An alarm that comes due while the machine was off still arrives, unless it is later than the grace window in `cli/src/reminders.c`, in which case it expires without a toast.

The shell never judges lateness, and the CLI never schedules. Keep it that way: two owners of "is this still owed" would disagree after a suspend.

## Sweeps

A write that changes a dated item sweeps reminders, and the shell runs `sweep` shortly after it loads. A sweep fires or expires everything due, so an alarm is not missed because the shell was down when it came due.

## The bar mark

The bar lights for what is owed today: open to-dos due before the end of the local day, overdue ones included. It is computed in `Service.qml` from the pulled index, on the same tick.
