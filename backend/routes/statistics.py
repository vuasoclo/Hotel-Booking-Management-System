from fastapi import APIRouter, Query
from typing import Optional
from utils.db import execute

router = APIRouter(prefix="/api/statistics", tags=["Statistics"])

@router.get("")
def get_statistics(
    period: str = Query("all", enum=["all", "this_month", "last_month", "this_quarter"]),
    room_type_id: Optional[int] = Query(None)
):
    """Lấy dữ liệu dashboard: KPI, occupancy heatmap, revenue chart có hỗ trợ filter."""
    
    # 1. Xây dựng điều kiện lọc (WHERE clauses)
    occ_where = ["1=1"]
    rev_where = ["1=1"]
    bk_where = ["status NOT IN ('Cancelled', 'Pending')"]
    
    if room_type_id:
        occ_where.append(f"v.room_type_id = {room_type_id}")
        # Note: v_monthly_revenue không có room_type_id vì nó đã sum theo booking. 
        # Nếu muốn lọc doanh thu theo loại phòng, cần join sâu hơn, 
        # nhưng ở đây ta ưu tiên hiệu năng và cấu trúc view hiện tại.
    
    if period == "this_month":
        occ_where.append("DATE_TRUNC('month', v.date) = DATE_TRUNC('month', CURRENT_DATE)")
        rev_where.append("DATE_TRUNC('month', report_month) = DATE_TRUNC('month', CURRENT_DATE)")
        bk_where.append("DATE_TRUNC('month', check_out) = DATE_TRUNC('month', CURRENT_DATE)")
    elif period == "last_month":
        occ_where.append("DATE_TRUNC('month', v.date) = DATE_TRUNC('month', CURRENT_DATE - INTERVAL '1 month')")
        rev_where.append("DATE_TRUNC('month', report_month) = DATE_TRUNC('month', CURRENT_DATE - INTERVAL '1 month')")
        bk_where.append("DATE_TRUNC('month', check_out) = DATE_TRUNC('month', CURRENT_DATE - INTERVAL '1 month')")
    elif period == "this_quarter":
        occ_where.append("DATE_TRUNC('quarter', v.date) = DATE_TRUNC('quarter', CURRENT_DATE)")
        rev_where.append("DATE_TRUNC('quarter', report_month) = DATE_TRUNC('quarter', CURRENT_DATE)")
        bk_where.append("DATE_TRUNC('quarter', check_out) = DATE_TRUNC('quarter', CURRENT_DATE)")

    # 2. Thực thi các query
    occupancy_query = f"""
        SELECT v.*, rt.type_name 
        FROM v_daily_occupancy v
        JOIN room_types rt ON v.room_type_id = rt.id
        WHERE {" AND ".join(occ_where)}
        ORDER BY v.date DESC
        LIMIT 100
    """
    occupancy = execute(occupancy_query, fetch="all")
    
    revenue_query = f"""
        SELECT * FROM v_monthly_revenue 
        WHERE {" AND ".join(rev_where)}
        ORDER BY report_month DESC 
        LIMIT 12
    """
    revenue = execute(revenue_query, fetch="all")

    kpi_query = f"""
        WITH occ_total AS (
            SELECT 
                COALESCE(SUM(total_reserved), 0) AS total_res,
                COALESCE(SUM(CASE WHEN date >= CURRENT_DATE - INTERVAL '7 days' AND date <= CURRENT_DATE THEN total_reserved ELSE 0 END), 0) AS res_7d,
                COALESCE(SUM(CASE WHEN date >= CURRENT_DATE - INTERVAL '7 days' AND date <= CURRENT_DATE THEN total_inventory ELSE 0 END), 0) AS inv_7d
            FROM v_daily_occupancy v
            WHERE {" AND ".join(occ_where)}
        ),
        rev_total AS (
            SELECT 
                COALESCE(SUM(total_revenue), 0) AS total_revenue,
                COALESCE(SUM(actual_collected), 0) AS total_collected,
                COALESCE(SUM(total_room_cost), 0) AS total_room_revenue
            FROM v_monthly_revenue
            WHERE {" AND ".join(rev_where).replace('report_month', 'report_month')}
        ),
        booking_count AS (
            SELECT COUNT(*) AS total_bookings
            FROM bookings
            WHERE {" AND ".join(bk_where)}
        )
        SELECT 
            CASE WHEN o.inv_7d = 0 THEN 0 ELSE ROUND((o.res_7d * 100.0) / o.inv_7d, 1) END AS avg_occupancy_7d,
            r.total_revenue,
            r.total_collected,
            (r.total_revenue - r.total_collected) AS total_outstanding,
            CASE WHEN o.total_res = 0 THEN 0 ELSE ROUND(r.total_room_revenue / o.total_res, 0) END AS adr,
            b.total_bookings AS bookings_count
        FROM occ_total o CROSS JOIN rev_total r CROSS JOIN booking_count b
    """
    kpis = execute(kpi_query, fetch="one")
    
    if not kpis:
        kpis = {
            "avg_occupancy_7d": 0, "total_revenue": 0, "total_collected": 0, 
            "total_outstanding": 0, "adr": 0, "bookings_count": 0
        }

    return {
        "kpis": kpis,
        "daily_occupancy": occupancy or [],
        "monthly_revenue": revenue or [],
    }

