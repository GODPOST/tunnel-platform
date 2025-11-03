#!/bin/bash
# quick_fix.sh - Fix common issues and verify setup

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════╗"
echo "║   Tunnel Platform - Quick Fix & Verify       ║"
echo "╚═══════════════════════════════════════════════╝"
echo -e "${NC}"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if port is in use
port_in_use() {
    lsof -i:$1 >/dev/null 2>&1
}

# 1. Check prerequisites
echo -e "${YELLOW}🔍 Checking prerequisites...${NC}"

if command_exists python3; then
    PYTHON_VERSION=$(python3 --version)
    echo -e "${GREEN}✓ Python: ${PYTHON_VERSION}${NC}"
else
    echo -e "${RED}✗ Python not found${NC}"
fi

if command_exists node; then
    NODE_VERSION=$(node --version)
    echo -e "${GREEN}✓ Node: ${NODE_VERSION}${NC}"
else
    echo -e "${RED}✗ Node not found${NC}"
fi

if command_exists npm; then
    NPM_VERSION=$(npm --version)
    echo -e "${GREEN}✓ npm: ${NPM_VERSION}${NC}"
else
    echo -e "${RED}✗ npm not found${NC}"
fi

# 2. Check .env file
echo -e "\n${YELLOW}📄 Checking .env file...${NC}"

if [ ! -f .env ]; then
    echo -e "${RED}✗ .env file not found!${NC}"
    echo -e "${YELLOW}Creating template .env file...${NC}"
    
    cat > .env << 'EOF'
# AWS Configuration
AWS_ACCESS_KEY_ID=your_access_key_here
AWS_SECRET_ACCESS_KEY=your_secret_key_here
AWS_REGION=us-east-1
AMI_ID=ami-0866a3c8686eaeeba
SECURITY_GROUP_ID=your_security_group_id
SSH_USERNAME=ubuntu
SSH_KEY_PATH=secrets/aws-tunnel-key
EC2_KEY_NAME=tunnel-key

# Security
SECRET_KEY=$(openssl rand -hex 32)
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=10080

# Database
DATABASE_URL=sqlite:///./tunnel_platform.db

# Network
WG_SUBNET_PREFIX=10.10.0
WG_PORT=51820

# Frontend
FRONTEND_URL=http://localhost:5173

# Limits
MAX_INSTANCES_PER_USER=5
MAX_PEERS_PER_INSTANCE=10
EOF
    
    # Generate SECRET_KEY
    SECRET_KEY=$(openssl rand -hex 32)
    sed -i.bak "s/\$(openssl rand -hex 32)/$SECRET_KEY/" .env
    rm .env.bak
    
    echo -e "${GREEN}✓ Created .env template${NC}"
    echo -e "${YELLOW}⚠️  IMPORTANT: Edit .env and add your AWS credentials!${NC}"
else
    echo -e "${GREEN}✓ .env file exists${NC}"
    
    # Check for required variables
    REQUIRED_VARS=("AWS_ACCESS_KEY_ID" "AWS_SECRET_ACCESS_KEY" "SECRET_KEY")
    MISSING_VARS=()
    
    for var in "${REQUIRED_VARS[@]}"; do
        if ! grep -q "^${var}=" .env || grep -q "^${var}=.*your.*here" .env; then
            MISSING_VARS+=("$var")
        fi
    done
    
    if [ ${#MISSING_VARS[@]} -gt 0 ]; then
        echo -e "${YELLOW}⚠️  Missing or incomplete variables:${NC}"
        for var in "${MISSING_VARS[@]}"; do
            echo -e "   - ${var}"
        done
    fi
    
    # Generate SECRET_KEY if missing
    if ! grep -q "^SECRET_KEY=" .env || grep -q "^SECRET_KEY=$" .env; then
        SECRET_KEY=$(openssl rand -hex 32)
        echo "SECRET_KEY=$SECRET_KEY" >> .env
        echo -e "${GREEN}✓ Generated SECRET_KEY${NC}"
    fi
fi

# 3. Fix .env parsing issues
echo -e "\n${YELLOW}🔧 Fixing .env parsing issues...${NC}"

if [ -f .env ]; then
    # Remove any ssh commands or invalid lines
    grep -v "^ssh -i" .env > .env.tmp || true
    grep -v "^\$(" .env.tmp > .env.clean || true
    mv .env.clean .env
    rm -f .env.tmp
    echo -e "${GREEN}✓ Cleaned .env file${NC}"
fi

# 4. Check/create directory structure
echo -e "\n${YELLOW}📁 Checking directory structure...${NC}"

DIRS=("backend" "frontend/src" "frontend/public" "configs" "secrets")

for dir in "${DIRS[@]}"; do
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        echo -e "${GREEN}✓ Created $dir${NC}"
    else
        echo -e "${GREEN}✓ $dir exists${NC}"
    fi
done

# 5. Check backend files
echo -e "\n${YELLOW}🔍 Checking backend files...${NC}"

BACKEND_FILES=("app.py" "models.py" "auth.py" "utils.py" "userdata.sh")

for file in "${BACKEND_FILES[@]}"; do
    if [ -f "backend/$file" ] || [ -f "$file" ]; then
        echo -e "${GREEN}✓ $file exists${NC}"
    else
        echo -e "${RED}✗ $file missing${NC}"
    fi
done

# 6. Check if ports are available
echo -e "\n${YELLOW}🔌 Checking ports...${NC}"

if port_in_use 8000; then
    echo -e "${YELLOW}⚠️  Port 8000 is in use (backend might be running)${NC}"
    echo -e "   To stop: ${GREEN}pkill -f 'python.*app.py'${NC}"
else
    echo -e "${GREEN}✓ Port 8000 is available${NC}"
fi

if port_in_use 5173; then
    echo -e "${YELLOW}⚠️  Port 5173 is in use (frontend might be running)${NC}"
    echo -e "   To stop: ${GREEN}pkill -f 'vite'${NC}"
else
    echo -e "${GREEN}✓ Port 5173 is available${NC}"
fi

# 7. Check/install backend dependencies
echo -e "\n${YELLOW}📦 Checking backend dependencies...${NC}"

if [ -f requirements.txt ]; then
    if [ ! -d "venv" ]; then
        echo -e "${YELLOW}Creating virtual environment...${NC}"
        python3 -m venv venv
        echo -e "${GREEN}✓ Virtual environment created${NC}"
    fi
    
    echo -e "${YELLOW}Installing/updating dependencies...${NC}"
    source venv/bin/activate
    pip install -q --upgrade pip
    pip install -q -r requirements.txt
    echo -e "${GREEN}✓ Backend dependencies installed${NC}"
else
    echo -e "${RED}✗ requirements.txt not found${NC}"
fi

# 8. Initialize database
echo -e "\n${YELLOW}🗄️  Initializing database...${NC}"

if [ -f init_db.py ]; then
    python3 init_db.py
else
    echo -e "${YELLOW}Creating init_db.py...${NC}"
    cat > init_db.py << 'PYEOF'
import os
from sqlalchemy import create_engine
from models import Base

DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./tunnel_platform.db")

def init_database():
    print("🔧 Initializing database...")
    engine = create_engine(DATABASE_URL, connect_args={"check_same_thread": False} if "sqlite" in DATABASE_URL else {})
    Base.metadata.create_all(bind=engine)
    print("✅ Database initialized!")

if __name__ == "__main__":
    init_database()
PYEOF
    python3 init_db.py
fi

# 9. Check frontend dependencies
echo -e "\n${YELLOW}📦 Checking frontend dependencies...${NC}"

if [ -d "frontend" ]; then
    cd frontend
    if [ ! -d "node_modules" ]; then
        echo -e "${YELLOW}Installing frontend dependencies...${NC}"
        npm install
        echo -e "${GREEN}✓ Frontend dependencies installed${NC}"
    else
        echo -e "${GREEN}✓ Frontend dependencies exist${NC}"
    fi
    cd ..
fi

# 10. Test backend connection
echo -e "\n${YELLOW}🧪 Testing backend (if running)...${NC}"

if port_in_use 8000; then
    if command_exists curl; then
        HEALTH_CHECK=$(curl -s http://localhost:8000/health || echo "failed")
        if [[ $HEALTH_CHECK == *"healthy"* ]]; then
            echo -e "${GREEN}✓ Backend is responding${NC}"
        else
            echo -e "${YELLOW}⚠️  Backend might not be fully ready${NC}"
        fi
    fi
else
    echo -e "${YELLOW}⚠️  Backend is not running${NC}"
fi

# 11. Create start scripts
echo -e "\n${YELLOW}📝 Creating start scripts...${NC}"

# Backend start script
cat > start_backend.sh << 'EOF'
#!/bin/bash
cd backend 2>/dev/null || true
source venv/bin/activate 2>/dev/null || source ../venv/bin/activate
python app.py
EOF
chmod +x start_backend.sh
echo -e "${GREEN}✓ Created start_backend.sh${NC}"

# Frontend start script
cat > start_frontend.sh << 'EOF'
#!/bin/bash
cd frontend
npm run dev
EOF
chmod +x start_frontend.sh
echo -e "${GREEN}✓ Created start_frontend.sh${NC}"

# Combined start script
cat > start_all.sh << 'EOF'
#!/bin/bash
echo "🚀 Starting Tunnel Platform..."

# Start backend in background
echo "Starting backend..."
./start_backend.sh &
BACKEND_PID=$!

# Wait a bit for backend to start
sleep 3

# Start frontend
echo "Starting frontend..."
./start_frontend.sh

# When frontend exits, kill backend
kill $BACKEND_PID 2>/dev/null
EOF
chmod +x start_all.sh
echo -e "${GREEN}✓ Created start_all.sh${NC}"

# Summary
echo -e "\n${GREEN}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              Setup Complete! ✅                ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════╝${NC}"

echo -e "\n${BLUE}📋 Next Steps:${NC}"
echo -e "1. ${YELLOW}Edit .env file with your AWS credentials${NC}"
echo -e "   ${GREEN}nano .env${NC}"
echo -e ""
echo -e "2. ${YELLOW}Start the backend:${NC}"
echo -e "   ${GREEN}./start_backend.sh${NC}"
echo -e "   ${BLUE}or manually:${NC}"
echo -e "   ${GREEN}cd backend && source venv/bin/activate && python app.py${NC}"
echo -e ""
echo -e "3. ${YELLOW}In another terminal, start the frontend:${NC}"
echo -e "   ${GREEN}./start_frontend.sh${NC}"
echo -e "   ${BLUE}or manually:${NC}"
echo -e "   ${GREEN}cd frontend && npm run dev${NC}"
echo -e ""
echo -e "4. ${YELLOW}Or start both at once:${NC}"
echo -e "   ${GREEN}./start_all.sh${NC}"
echo -e ""
echo -e "5. ${YELLOW}Open browser and navigate to:${NC}"
echo -e "   ${GREEN}http://localhost:5173${NC}"
echo -e ""
echo -e "${BLUE}🔧 Useful Commands:${NC}"
echo -e "  ${GREEN}python test_connection.py${NC} - Test backend API"
echo -e "  ${GREEN}python setup_aws.py${NC} - Setup AWS resources"
echo -e "  ${GREEN}./quick_fix.sh${NC} - Run this script again"
echo -e ""
echo -e "${YELLOW}⚠️  Important:${NC}"
echo -e "  - Make sure AWS credentials are set in .env"
echo -e "  - Create SSH key pair in AWS Console named 'tunnel-key'"
echo -e "  - Or run: aws ec2 create-key-pair --key-name tunnel-key"
echo ""