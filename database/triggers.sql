CREATE OR REPLACE FUNCTION touch_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_rooms_updated ON rooms;
CREATE TRIGGER trg_rooms_updated
BEFORE UPDATE ON rooms
FOR EACH ROW
EXECUTE FUNCTION touch_updated_at();
DROP TRIGGER IF EXISTS trg_bookings_updated ON bookings;
CREATE TRIGGER trg_bookings_updated
BEFORE UPDATE ON bookings
FOR EACH ROW
EXECUTE FUNCTION touch_updated_at();
CREATE OR REPLACE FUNCTION set_agreed_price()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.agreed_price IS NULL OR NEW.agreed_price = 0 THEN
        SELECT base_price INTO NEW.agreed_price
        FROM room_types
        WHERE id = NEW.room_type_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_snapshot_price ON booking_details;
CREATE TRIGGER trg_snapshot_price
BEFORE INSERT ON booking_details
FOR EACH ROW
EXECUTE FUNCTION set_agreed_price();
CREATE OR REPLACE FUNCTION release_inventory_on_cancel()
RETURNS TRIGGER AS $$
DECLARE
    r RECORD;
    v_cur_date DATE;
    v_end_date DATE;
BEGIN
    FOR r IN
        SELECT room_type_id, quantity
        FROM booking_details
        WHERE booking_id = NEW.id
    LOOP
        v_cur_date := NEW.check_in::DATE;
        v_end_date := NEW.check_out::DATE;
        WHILE v_cur_date < v_end_date LOOP
            UPDATE room_type_inventory
            SET total_reserved = GREATEST(total_reserved - r.quantity, 0)
            WHERE room_type_id = r.room_type_id
              AND date = v_cur_date;
            v_cur_date := v_cur_date + 1;
        END LOOP;
    END LOOP;
    UPDATE room_assignments
    SET is_cancelled = TRUE
    WHERE booking_id = NEW.id
      AND is_cancelled = FALSE;
    IF NEW.cancelled_at IS NULL THEN
        NEW.cancelled_at := NOW();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_release_inventory_on_cancel ON bookings;
CREATE TRIGGER trg_release_inventory_on_cancel
BEFORE UPDATE ON bookings
FOR EACH ROW
WHEN (NEW.status = 'Cancelled' AND OLD.status <> 'Cancelled')
EXECUTE FUNCTION release_inventory_on_cancel();

CREATE OR REPLACE FUNCTION sync_total_amount()
RETURNS TRIGGER AS $$
DECLARE
    v_new_booking_id INT;
    v_old_booking_id INT;
BEGIN
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        v_new_booking_id := NEW.booking_id;
    END IF;
    IF TG_OP IN ('DELETE', 'UPDATE') THEN
        v_old_booking_id := OLD.booking_id;
    END IF;
    IF TG_OP = 'UPDATE' AND v_old_booking_id IS DISTINCT FROM v_new_booking_id THEN
        PERFORM recalculate_booking_total(v_old_booking_id);
        PERFORM recalculate_booking_total(v_new_booking_id);
    ELSE
        PERFORM recalculate_booking_total(COALESCE(v_new_booking_id, v_old_booking_id));
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_sync_total_amount ON service_usage;
CREATE TRIGGER trg_sync_total_amount
AFTER INSERT OR UPDATE OR DELETE ON service_usage
FOR EACH ROW
EXECUTE FUNCTION sync_total_amount();
DROP TRIGGER IF EXISTS trg_sync_total_amount_bd ON booking_details;
CREATE TRIGGER trg_sync_total_amount_bd
AFTER INSERT OR UPDATE OR DELETE ON booking_details
FOR EACH ROW
EXECUTE FUNCTION sync_total_amount();
DROP TRIGGER IF EXISTS trg_sync_total_amount_bs ON booking_surcharges;
CREATE TRIGGER trg_sync_total_amount_bs
AFTER INSERT OR UPDATE OR DELETE ON booking_surcharges
FOR EACH ROW
EXECUTE FUNCTION sync_total_amount();
