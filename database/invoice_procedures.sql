CREATE OR REPLACE PROCEDURE issue_invoice(
    p_booking_id INT,
    p_staff_id   INT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_status    booking_status;
    v_total     DECIMAL(10,2);
    v_paid      DECIMAL(10,2);
BEGIN
    SELECT status, total_amount, amount_paid
    INTO v_status, v_total, v_paid
    FROM bookings WHERE id = p_booking_id FOR UPDATE;
    IF v_status NOT IN ('Active', 'Checked-in', 'Completed') THEN
        RAISE EXCEPTION 'BOOKING_STATE_INVALID: Không thể xuất hóa đơn cho booking trạng thái %', v_status
        USING ERRCODE = 'P0016';
    END IF;
    INSERT INTO invoices (booking_id, issued_by, total_amount, amount_paid, balance, status)
    VALUES (p_booking_id, p_staff_id, v_total, v_paid, v_total - v_paid, 'Issued')
    ON CONFLICT (booking_id) DO UPDATE
        SET total_amount = EXCLUDED.total_amount,
            amount_paid  = EXCLUDED.amount_paid,
            balance      = EXCLUDED.balance,
            status       = 'Issued',
            issued_at    = NOW(),
            issued_by    = EXCLUDED.issued_by
    WHERE invoices.status <> 'Void';
END;
$$;

CREATE OR REPLACE PROCEDURE record_payment(
    p_booking_id INT,
    p_amount     DECIMAL(10,2),
    p_staff_id   INT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_status    booking_status;
    v_total     DECIMAL(10,2);
    v_paid      DECIMAL(10,2);
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'INVALID_AMOUNT: Số tiền thanh toán phải > 0'
        USING ERRCODE = 'P0021';
    END IF;
    SELECT status, total_amount, amount_paid
    INTO v_status, v_total, v_paid
    FROM bookings WHERE id = p_booking_id FOR UPDATE;
    IF v_status NOT IN ('Active', 'Checked-in', 'Completed') THEN
        RAISE EXCEPTION 'BOOKING_STATE_INVALID: Không thể thanh toán cho booking trạng thái %', v_status
        USING ERRCODE = 'P0017';
    END IF;
    IF v_paid + p_amount > v_total THEN
        RAISE EXCEPTION 'OVERPAYMENT: Vượt quá tổng hóa đơn. Còn lại cần thanh toán: %', (v_total - v_paid)
        USING ERRCODE = 'P0018';
    END IF;
    UPDATE bookings
    SET amount_paid = amount_paid + p_amount,
        updated_by  = p_staff_id
    WHERE id = p_booking_id;
    UPDATE invoices
    SET amount_paid = amount_paid + p_amount,
        balance     = balance - p_amount,
        status      = CASE
                        WHEN (amount_paid + p_amount) >= total_amount THEN 'Paid'::invoice_status
                        ELSE 'Issued'::invoice_status
                      END
    WHERE booking_id = p_booking_id
      AND status <> 'Void';
END;
$$;
