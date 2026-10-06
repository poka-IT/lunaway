-- The end of the window `opening_intervals` covers, so an offline device can
-- tell "closed" (no interval before this instant) from "not computed" (past
-- it). NULL when there are no intervals. The next `lunaway conflate` fills it
-- for the places that have intervals, and gives them a new position in the
-- change feed so devices receive it.

ALTER TABLE places ADD COLUMN opening_intervals_until timestamptz;
