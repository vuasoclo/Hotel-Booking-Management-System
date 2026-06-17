from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
import os
from routes import auth, calendar, rooms, customers, bookings, services, statistics

app = FastAPI(
    title="HBMS — Hotel Booking Management System",
    description="Backend API.",
    version="2.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(calendar.router)
app.include_router(rooms.router)
app.include_router(customers.router)
app.include_router(bookings.router)
app.include_router(services.router)
app.include_router(statistics.router)

FRONTEND_DIR = os.path.join(os.path.dirname(__file__), "..", "frontend")
if os.path.exists(FRONTEND_DIR):
    app.mount("/frontend", StaticFiles(directory=FRONTEND_DIR), name="frontend")

@app.get("/")
def read_root():
    return {"message": "HBMS API is running. Visit /docs for documentation."}
