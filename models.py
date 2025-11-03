from sqlalchemy import Column, Integer, String, ForeignKey, DateTime, Boolean
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import relationship
from datetime import datetime

Base = declarative_base()

class User(Base):
    __tablename__ = "users"
    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, unique=True, index=True)
    password_hash = Column(String)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    
    instances = relationship("Instance", back_populates="user")

class Instance(Base):
    __tablename__ = "instances"
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"))
    aws_instance_id = Column(String, unique=True, index=True)
    region = Column(String)
    public_ip = Column(String)
    state = Column(String, default="launching")  # launching, running, stopped, terminated
    instance_type = Column(String, default="t2.micro")
    created_at = Column(DateTime, default=datetime.utcnow)
    
    user = relationship("User", back_populates="instances")
    peers = relationship("Peer", back_populates="instance")
    alloc_state = relationship("AllocState", uselist=False, back_populates="instance")

class Peer(Base):
    __tablename__ = "peers"
    id = Column(Integer, primary_key=True, index=True)
    instance_id = Column(Integer, ForeignKey("instances.id"))
    name = Column(String)
    device_type = Column(String)  # laptop, phone, tablet
    wg_public_key = Column(String)
    wg_private_key = Column(String)  # In production, encrypt this!
    assigned_ip = Column(String)
    created_at = Column(DateTime, default=datetime.utcnow)
    last_connected = Column(DateTime, nullable=True)
    
    instance = relationship("Instance", back_populates="peers")

class AllocState(Base):
    __tablename__ = "alloc_state"
    instance_id = Column(Integer, ForeignKey("instances.id"), primary_key=True)
    last_octet = Column(Integer, default=2)  # Start from .3 (.2 used by userdata)
    
    instance = relationship("Instance", back_populates="alloc_state")