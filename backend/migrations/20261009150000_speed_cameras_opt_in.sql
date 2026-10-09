-- Speed cameras: in France a user may ask, by an explicit setting of the
-- app, for the cameras' exact positions in place of the danger zones
-- (lunaway_domain::enforcement::RULES, `opt_in`; docs/speed-cameras.md).
--
-- A camera whose form depends on such a choice gets two items: one for the
-- clients that did not make it (`default`, a zone) and one for those that
-- did (`opt_in`, a point); every other camera keeps one item for everyone
-- (`all`). `opt_in_countries` names the choices the camera's form depends
-- on: a client gets the `opt_in` item once it made every one of them, the
-- `default` item otherwise. An array rather than one country: a camera
-- within a kilometre of two countries that each offer a choice needs
-- both, and a choice only turns zones into points, so a client that made
-- one of them and not the other still gets the zone.
ALTER TABLE enforcement_items
    ADD COLUMN variant text NOT NULL DEFAULT 'all',
    ADD COLUMN opt_in_countries text[];

ALTER TABLE enforcement_items
    ADD CONSTRAINT enforcement_items_variant_check CHECK (
        (variant = 'all' AND opt_in_countries IS NULL)
        OR (variant IN ('default', 'opt_in')
            AND cardinality(opt_in_countries) >= 1
            AND array_position(opt_in_countries, NULL) IS NULL
            AND array_to_string(opt_in_countries, ',') ~ '^[A-Z]{2}(,[A-Z]{2})*$'));

-- A camera has at most one item for the clients without the choice (`all`
-- or `default`) and one for those with it (`opt_in`). The first keeps its
-- row and its id when the camera's form starts or stops depending on a
-- choice (`all` to `default` and back), so a client without the choice
-- sees an update, never a removal and a new item; a unique (device_key,
-- variant) would insert a second row with the same id.
ALTER TABLE enforcement_items DROP CONSTRAINT enforcement_items_device_key_key;
CREATE UNIQUE INDEX enforcement_items_slot_key
    ON enforcement_items (device_key, (variant = 'opt_in'));

-- The API reads which clients an item is for; it still reads neither
-- `device_key` nor `content_hash`.
GRANT SELECT (variant, opt_in_countries) ON enforcement_items TO lunaway_app;
