from fastapi import FastAPI, Depends, HTTPException, BackgroundTasks, status
from fastapi.security import OAuth2PasswordRequestForm
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, Session
from pydantic import BaseModel, EmailStr, field_validator
import os
import logging
from datetime import datetime, timezone
from dotenv import load_dotenv
import asyncio
import qrcode
from io import BytesIO
import base64

load_dotenv()

MAX_INSTANCES_PER_USER = int(os.getenv("MAX_INSTANCES_PER_USER", 3))

from models import Base, User, Instance, Peer, AllocState
from auth import get_password_hash, verify_password, create_access_token, decode_token, oauth2_scheme
from utils import launch_instance_async, stop_instance, terminate_instance, WG_SUBNET_PREFIX, WG_PORT

# Logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[logging.FileHandler('app.log'), logging.StreamHandler()]
)
logger = logging.getLogger(__name__)

# Database
DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./tunnel_platform.db")
engine = create_engine(
    DATABASE_URL,
    connect_args={"check_same_thread": False} if "sqlite" in DATABASE_URL else {},
    pool_pre_ping=True,
    pool_size=10,
    max_overflow=20
)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base.metadata.create_all(bind=engine)

# FastAPI
app = FastAPI(title="Tunnel Platform API", version="2.0.0")

# CORS - Allow all for development
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, specify exact origins
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/api/health")
@app.get("/health")
async def health_check():
    return {"status": "healthy", "timestamp": datetime.now(timezone.utc).isoformat()}

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

async def get_current_user(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)):
    try:
        payload = decode_token(token)
        email = payload.get("sub")
        if not email:
            raise HTTPException(status_code=401, detail="Invalid token")
        user = db.query(User).filter(User.email == email).first()
        if not user:
            raise HTTPException(status_code=401, detail="User not found")
        return user
    except Exception as e:
        logger.error(f"Auth error: {str(e)}")
        raise HTTPException(status_code=401, detail="Invalid token")

# Pydantic models
class UserCreate(BaseModel):
    email: EmailStr
    password: str
    
    @field_validator('password')
    @classmethod
    def password_length(cls, v: str) -> str:
        if len(v) < 8:
            raise ValueError('Password must be at least 8 characters')
        return v

class InstanceCreate(BaseModel):
    region: str = "us-east-1"
    instance_type: str = "t2.micro"

class PeerCreate(BaseModel):
    name: str
    device_type: str = "phone"

# Background task with proper session management
async def launch_instance_task(instance_id: int):
    """Background task with its own DB session"""
    db = SessionLocal()
    try:
        instance = db.query(Instance).filter(Instance.id == instance_id).first()
        if instance:
            await launch_instance_async(db, instance)
    except Exception as e:
        logger.error(f"Background launch error: {str(e)}")
        if instance:
            instance.state = "failed"
            db.commit()
    finally:
        db.close()

# ==================== AUTH ENDPOINTS ====================
@app.post("/api/auth/register")
async def register(user_data: UserCreate, db: Session = Depends(get_db)):
    try:
        if db.query(User).filter(User.email == user_data.email).first():
            raise HTTPException(status_code=400, detail="Email already registered")
        
        hashed = get_password_hash(user_data.password)
        user = User(email=user_data.email, password_hash=hashed)
        db.add(user)
        db.commit()
        db.refresh(user)
        logger.info(f"New user registered: {user_data.email}")
        return {"message": "User created", "email": user.email}
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Registration error: {str(e)}")
        db.rollback()
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/auth/login")
async def login(form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    try:
        user = db.query(User).filter(User.email == form_data.username).first()
        if not user or not verify_password(form_data.password, user.password_hash):
            raise HTTPException(status_code=401, detail="Incorrect email or password")
        
        token = create_access_token({"sub": user.email})
        logger.info(f"User logged in: {user.email}")
        return {"access_token": token, "token_type": "bearer"}
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Login error: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

# ==================== INSTANCE ENDPOINTS ====================
@app.get("/api/instances")
async def list_instances(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """List all user instances - FIXED FORMAT"""
    try:
        instances = db.query(Instance).filter(Instance.user_id == current_user.id).order_by(Instance.created_at.desc()).all()
        
        result = []
        for inst in instances:
            peer_count = db.query(Peer).filter(Peer.instance_id == inst.id).count()
            result.append({
                "id": inst.id,
                "state": inst.state,
                "public_ip": inst.public_ip,
                "aws_instance_id": inst.aws_instance_id,
                "instance_type": inst.instance_type,
                "region": inst.region,
                "created_at": inst.created_at.isoformat() if inst.created_at else None,
                "peer_count": peer_count
            })
        
        return result  # Return list directly for frontend compatibility
    except Exception as e:
        logger.error(f"List instances error: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/instances")
async def create_instance(
    instance_data: InstanceCreate,
    background_tasks: BackgroundTasks,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    try:
        # Check instance limit
        count = db.query(Instance).filter(Instance.user_id == current_user.id).count()
        if count >= MAX_INSTANCES_PER_USER:
            raise HTTPException(status_code=400, detail=f"Maximum {MAX_INSTANCES_PER_USER} instances allowed")

        # Create instance record
        instance = Instance(
            user_id=current_user.id,
            region=instance_data.region,
            instance_type=instance_data.instance_type,
            state="launching"
        )
        db.add(instance)
        db.commit()
        db.refresh(instance)

        logger.info(f"Instance {instance.id} created for {current_user.email}")

        # Launch in background
        background_tasks.add_task(launch_instance_task, instance.id)

        return {
            "message": "Instance launching...",
            "instance_id": instance.id,
            "state": "launching"
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Create instance error: {str(e)}")
        db.rollback()
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/api/instances/{instance_id}")
async def delete_instance(
    instance_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    try:
        instance = db.query(Instance).filter(
            Instance.id == instance_id,
            Instance.user_id == current_user.id
        ).first()
        
        if not instance:
            raise HTTPException(status_code=404, detail="Instance not found")
        
        # Terminate AWS instance if exists
        if instance.aws_instance_id:
            try:
                terminate_instance(instance.aws_instance_id)
            except Exception as e:
                logger.error(f"AWS termination error: {str(e)}")
        
        # Delete all peers
        db.query(Peer).filter(Peer.instance_id == instance_id).delete()
        
        # Delete allocation state
        db.query(AllocState).filter(AllocState.instance_id == instance_id).delete()
        
        # Delete instance
        db.delete(instance)
        db.commit()
        
        logger.info(f"Instance {instance_id} deleted")
        return {"message": "Instance deleted"}
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Delete instance error: {str(e)}")
        db.rollback()
        raise HTTPException(status_code=500, detail=str(e))

# ==================== PEER ENDPOINTS ====================
@app.get("/api/instances/{instance_id}/peers")
async def list_peers(
    instance_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """List all peers for an instance"""
    try:
        instance = db.query(Instance).filter(
            Instance.id == instance_id,
            Instance.user_id == current_user.id
        ).first()
        
        if not instance:
            raise HTTPException(status_code=404, detail="Instance not found")
        
        peers = db.query(Peer).filter(Peer.instance_id == instance_id).order_by(Peer.created_at.desc()).all()
        
        result = []
        for peer in peers:
            result.append({
                "id": peer.id,
                "name": peer.name,
                "device_type": peer.device_type,
                "assigned_ip": peer.assigned_ip,
                "created_at": peer.created_at.isoformat() if peer.created_at else None
            })
        
        return result  # Return list directly
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"List peers error: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/instances/{instance_id}/peers")
async def create_peer(
    instance_id: int,
    peer_data: PeerCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    try:
        # Verify instance exists and belongs to user
        instance = db.query(Instance).filter(
            Instance.id == instance_id,
            Instance.user_id == current_user.id
        ).first()
        
        if not instance:
            raise HTTPException(status_code=404, detail="Instance not found")
        
        if instance.state != "running":
            raise HTTPException(status_code=400, detail="Instance not ready. Wait for it to be running.")
        
        # Get or create allocation state
        alloc = db.query(AllocState).filter(AllocState.instance_id == instance.id).first()
        if not alloc:
            alloc = AllocState(instance_id=instance.id, last_octet=2)
            db.add(alloc)
            db.commit()
            db.refresh(alloc)
        
        # Allocate IP
        next_octet = alloc.last_octet + 1
        if next_octet >= 254:
            raise HTTPException(status_code=400, detail="IP pool exhausted")
        
        peer_ip = f"{WG_SUBNET_PREFIX}.{next_octet}"
        
        # Create peer
        peer = Peer(
            instance_id=instance.id,
            name=peer_data.name,
            device_type=peer_data.device_type,
            assigned_ip=peer_ip
        )
        db.add(peer)
        
        # Update allocation
        alloc.last_octet = next_octet
        db.commit()
        db.refresh(peer)
        
        # Generate config file
        os.makedirs(f"configs/{instance.id}", exist_ok=True)
        config = f"""[Interface]
PrivateKey = <GENERATE_ON_CLIENT>
Address = {peer_ip}/32
DNS = 1.1.1.1, 8.8.8.8

[Peer]
PublicKey = <SERVER_PUBLIC_KEY>
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = {instance.public_ip}:{WG_PORT}
PersistentKeepalive = 25
"""
        config_path = f"configs/{instance.id}/peer_{peer.id}.conf"
        with open(config_path, "w") as f:
            f.write(config)
        
        logger.info(f"Peer {peer.id} created with IP {peer_ip}")
        
        return {
            "peer_id": peer.id,
            "ip": peer_ip,
            "name": peer.name,
            "message": "Peer created successfully"
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Create peer error: {str(e)}")
        db.rollback()
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/peers/{peer_id}/config")
async def get_peer_config(
    peer_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Download peer configuration file"""
    try:
        peer = db.query(Peer).join(Instance).filter(
            Peer.id == peer_id,
            Instance.user_id == current_user.id
        ).first()
        
        if not peer:
            raise HTTPException(status_code=404, detail="Peer not found")
        
        config_path = f"configs/{peer.instance_id}/peer_{peer.id}.conf"
        if not os.path.exists(config_path):
            raise HTTPException(status_code=404, detail="Config file not found")
        
        with open(config_path, "r") as f:
            config = f.read()
        
        return {"config": config, "peer_name": peer.name}
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Get config error: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/peers/{peer_id}/qr")
async def get_peer_qr(
    peer_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Generate QR code for peer config"""
    try:
        peer = db.query(Peer).join(Instance).filter(
            Peer.id == peer_id,
            Instance.user_id == current_user.id
        ).first()
        
        if not peer:
            raise HTTPException(status_code=404, detail="Peer not found")
        
        config_path = f"configs/{peer.instance_id}/peer_{peer.id}.conf"
        if not os.path.exists(config_path):
            raise HTTPException(status_code=404, detail="Config not found")
        
        with open(config_path, "r") as f:
            config = f.read()
        
        # Generate QR code
        qr = qrcode.QRCode(
            version=1,
            error_correction=qrcode.constants.ERROR_CORRECT_L,
            box_size=10,
            border=4
        )
        qr.add_data(config)
        qr.make(fit=True)
        
        img = qr.make_image(fill_color="black", back_color="white")
        buf = BytesIO()
        img.save(buf, format="PNG")
        buf.seek(0)
        img_base64 = base64.b64encode(buf.getvalue()).decode()
        
        logger.info(f"QR code generated for peer {peer_id}")
        return {
            "qr_code": f"data:image/png;base64,{img_base64}",
            "peer_name": peer.name
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"QR generation error: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/api/peers/{peer_id}")
async def delete_peer(
    peer_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Delete a peer"""
    try:
        peer = db.query(Peer).join(Instance).filter(
            Peer.id == peer_id,
            Instance.user_id == current_user.id
        ).first()
        
        if not peer:
            raise HTTPException(status_code=404, detail="Peer not found")
        
        # Delete config file
        config_path = f"configs/{peer.instance_id}/peer_{peer.id}.conf"
        if os.path.exists(config_path):
            os.remove(config_path)
        
        # Delete peer
        db.delete(peer)
        db.commit()
        
        logger.info(f"Peer {peer_id} deleted")
        return {"message": "Peer deleted"}
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Delete peer error: {str(e)}")
        db.rollback()
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=int(os.getenv("PORT", 8000)), log_level="info")