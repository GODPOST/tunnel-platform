# init_db.py - Script to initialize database
import os
from sqlalchemy import create_engine
from models import Base

DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./tunnel_platform.db")

def init_database():
    """Initialize the database with all tables"""
    print("🔧 Initializing database...")
    
    engine = create_engine(DATABASE_URL, connect_args={"check_same_thread": False} if "sqlite" in DATABASE_URL else {})
    
    # Create all tables
    Base.metadata.create_all(bind=engine)
    
    print("✅ Database initialized successfully!")
    print(f"📍 Location: {DATABASE_URL}")
    
    # Show created tables
    print("\n📊 Created tables:")
    for table in Base.metadata.tables.keys():
        print(f"  - {table}")

if __name__ == "__main__":
    init_database()