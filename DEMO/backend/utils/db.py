import os
import psycopg2
from psycopg2.extras import RealDictCursor
from dotenv import load_dotenv
from fastapi import HTTPException

load_dotenv()

DB_CONFIG = {
    "dbname":   os.getenv("DB_NAME",     "hbms"),
    "user":     os.getenv("DB_USER",     "postgres"),
    "password": os.getenv("DB_PASSWORD", "postgres"),
    "host":     os.getenv("DB_HOST",     "db"),
    "port":     os.getenv("DB_PORT",     "5432"),
}

def get_conn():
    """Tạo kết nối mới tới PostgreSQL, trả về dict-based cursor."""
    return psycopg2.connect(**DB_CONFIG, cursor_factory=RealDictCursor)

def execute(sql: str, params: tuple = (), fetch: str = "none"):
    """Utility thực thi SQL và trả về kết quả."""
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(sql, params)
            if fetch == "one":
                result = cur.fetchone()
            elif fetch == "all":
                result = cur.fetchall()
            else:
                result = None
            conn.commit()
        return result
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=400, detail=str(e))
    finally:
        conn.close()
