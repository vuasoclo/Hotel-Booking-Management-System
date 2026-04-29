import os
import psycopg2
from psycopg2.extras import RealDictCursor
from dotenv import load_dotenv

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
