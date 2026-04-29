from fastapi import APIRouter
from utils.db import execute

router = APIRouter(prefix="/api/statistics", tags=["Statistics"])

@router.get("")
def get_statistics():
    """Lấy dữ liệu dashboard: KPI, occupancy heatmap, revenue chart."""
    occupancy = execute("SELECT * FROM v_daily_occupancy ORDER BY date DESC LIMIT 30", fetch="all")
    revenue   = execute("SELECT * FROM v_monthly_revenue ORDER BY report_month DESC LIMIT 12", fetch="all")
    return {
        "daily_occupancy": occupancy or [],
        "monthly_revenue": revenue or [],
    }
