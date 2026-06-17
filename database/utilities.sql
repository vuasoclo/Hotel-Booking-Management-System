CREATE OR REPLACE PROCEDURE reset_hbms_data()
LANGUAGE plpgsql
AS $$
BEGIN
    TRUNCATE TABLE
        invoices,
        service_usage,
        services,
        room_assignments,
        booking_surcharges,
        booking_details,
        bookings,
        room_type_inventory,
        rooms,
        room_types,
        surcharge_policies,
        staff,
        customers,
        hotels
    RESTART IDENTITY CASCADE;
END;
$$;
