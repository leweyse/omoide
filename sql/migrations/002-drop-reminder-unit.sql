-- The shell arms reminders now, so there is no unit name left to remember.
--
-- Dropped rather than left NULL: a column that records where an alarm lives is
-- a lie once alarms do not live anywhere but this table, and the next person
-- reading the schema would go looking for the scheduler that fills it in.
ALTER TABLE reminders DROP COLUMN unit;
