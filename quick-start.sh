#!/bin/bash
# quick-start.sh - One-command setup for Tunnel Platform

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════╗"
echo "║   Tunnel Platform - Quick Start Setup         ║"
echo "╔═══════════════════════════════════════════════╗"
echo -e "${NC}"

# Check prerequisites
echo -e "${YELLOW}🔍 Checking prerequisites...${NC}"

check_command() {
    if ! command -v $1 &> /dev/null; then
        echo -e "${RED}✗ $1 is not installed${NC}"
        echo -e "${YELLOW}Install $1 and try again${NC}"
        exit 1
    else
        echo -e "${GREEN}✓ $1 is installed${NC}"
    fi
}

check_command docker
check_command docker-compose
check_command git

# Create project structure
echo -e "\n${YELLOW}📁 Creating project structure...${NC}"

mkdir -p tunnel-platform/{backend,frontend/src,frontend/public,configs,.github/workflows}
cd tunnel-platform

# Initialize git if not already
if [ ! -d .git ]; then
    git init
    echo -e "${GREEN}✓ Git repository initialized${NC}"
fi

# Create .env file
echo -e "\n${YELLOW}⚙️  Setting up environment variables...${NC}"

if [ ! -f .env ]; then
    cat > .env << 'EOF'
# Security
SECRET_KEY=CHANGE_ME_TO_RANDOM_STRING
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=10080

# AWS Configuration
AWS_ACCESS_KEY_ID=your_aws_access_key_here
AWS_SECRET_ACCESS_KEY=your_aws_secret_key_here
AWS_REGION=us-east-1

# Database
DATABASE_URL=postgresql://tunnel:tunnel_pass@db:5432/tunnel_db

# Limits
MAX_INSTANCES_PER_USER=5
MAX_PEERS_PER_INSTANCE=10

# Network
WG_SUBNET_PREFIX=10.10.0
WG_PORT=51820

# Frontend (for production)
FRONTEND_URL=http://localhost
EOF

    # Generate random SECRET_KEY
    SECRET_KEY=$(openssl rand -hex 32)
    sed -i.bak "s/CHANGE_ME_TO_RANDOM_STRING/$SECRET_KEY/" .env
    rm .env.bak
    
    echo -e "${GREEN}✓ .env file created${NC}"
    echo -e "${YELLOW}⚠️  IMPORTANT: Edit .env and add your AWS credentials!${NC}"
else
    echo -e "${YELLOW}⚠️  .env file already exists, skipping...${NC}"
fi

# Create .gitignore
cat > .gitignore << 'EOF'
# Environment
.env
*.env.local

# Python
__pycache__/
*.py[cod]
*$py.class
*.so
.Python
venv/
env/
*.egg-info/
dist/
build/

# Node
node_modules/
npm-debug.log*
yarn-debug.log*
yarn-error.log*
dist/
.cache/

# Database
*.db
*.sqlite
*.sqlite3

# Configs
configs/
secrets/

# Logs
*.log
logs/

# IDE
.vscode/
.idea/
*.swp
*.swo

# OS
.DS_Store
Thumbs.db

# Docker
docker-compose.override.yml
EOF

echo -e "${GREEN}✓ .gitignore created${NC}"

# Create README
cat > README.md << 'EOF'
# Tunnel Platform

Personal VPN Management Platform - Deploy your own WireGuard VPN servers on AWS.

## Quick Start

1. Edit `.env` with your AWS credentials
2. Run: `./deploy.sh`
3. Access: http://localhost

## Documentation

See SETUP.md for detailed setup instructions.

## Features

- 🚀 One-click VPN server deployment on AWS
- 📱 Multi-device support with WireGuard
- 🔐 Secure authentication and encryption
- 📊 Instance and peer management
- 📲 QR code generation for mobile devices

## Tech Stack

- **Backend**: FastAPI + SQLAlchemy + PostgreSQL
- **Frontend**: React + Vite + TailwindCSS
- **Infrastructure**: Docker + AWS EC2
- **VPN**: WireGuard

## License

MIT
EOF

echo -e "${GREEN}✓ README.md created${NC}"

# Download/create necessary files
echo -e "\n${YELLOW}📥 Setting up application files...${NC}"
echo -e "${BLUE}ℹ️  You'll need to copy your existing backend files to ./backend/${NC}"
echo -e "${BLUE}ℹ️  And create the frontend in ./frontend/ using the provided React code${NC}"

# Create userdata.sh template
cat > backend/userdata.sh << 'EOF'
#!/bin/bash
set -e

# Update system
apt-get update
apt-get upgrade -y

# Install WireGuard
apt-get install -y wireguard qrencode

# Generate server keys
cd /etc/wireguard
umask 077
wg genkey | tee privatekey | wg pubkey > publickey

# Configure WireGuard
cat > /etc/wireguard/wg0.conf << 'WGCONF'
[Interface]
PrivateKey = $(cat privatekey)
Address = 10.10.0.1/24
ListenPort = 51820
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
WGCONF

# Enable IP forwarding
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

# Start WireGuard
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

# Signal completion
touch /var/lib/cloud/instance/wg-setup-complete
EOF

echo -e "${GREEN}✓ userdata.sh template created${NC}"

# Show next steps
echo -e "\n${GREEN}✅ Initial setup complete!${NC}\n"
echo -e "${BLUE}📝 Next steps:${NC}"
echo -e "1. ${YELLOW}Edit .env file and add your AWS credentials${NC}"
echo -e "2. ${YELLOW}Copy your backend files to ./backend/${NC}"
echo -e "   - app.py (or app_improved.py)"
echo -e "   - models.py"
echo -e "   - auth.py"
echo -e "   - utils.py"
echo -e "   - requirements.txt"
echo -e "3. ${YELLOW}Set up the frontend in ./frontend/${NC}"
echo -e "   - Copy the React code provided"
echo -e "   - Create package.json, vite.config.js, etc."
echo -e "4. ${YELLOW}Copy deployment files:${NC}"
echo -e "   - docker-compose.yml"
echo -e "   - Dockerfile.backend"
echo -e "   - Dockerfile.frontend"
echo -e "   - nginx.conf"
echo -e "   - deploy.sh"
echo -e "5. ${YELLOW}Run: chmod +x deploy.sh && ./deploy.sh${NC}\n"

echo -e "${BLUE}📖 For detailed instructions, see the setup guide.${NC}"
echo -e "${BLUE}🆘 For support, check the troubleshooting section.${NC}\n"

# Optional: Create basic project structure helper
read -p "Would you like to create a complete project template with placeholders? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "\n${YELLOW}📦 Creating project template...${NC}"
    
    # Backend structure
    touch backend/{app.py,models.py,auth.py,utils.py,requirements.txt,__init__.py}
    
    # Frontend structure
    mkdir -p frontend/{src,public}
    touch frontend/{package.json,vite.config.js,tailwind.config.js,postcss.config.js}
    touch frontend/index.html
    touch frontend/src/{App.jsx,main.jsx,index.css}
    
    # Docker files
    touch {Dockerfile.backend,Dockerfile.frontend,docker-compose.yml,nginx.conf}
    
    # Scripts
    touch deploy.sh
    chmod +x deploy.sh
    
    # GitHub Actions
    touch .github/workflows/deploy.yml
    
    echo -e "${GREEN}✓ Project template created${NC}"
    echo -e "${YELLOW}⚠️  Remember to fill in the files with actual code!${NC}"
fi

echo -e "\n${GREEN}🎉 Setup complete! Follow the next steps to get started.${NC}\n"

# Show directory structure
if command -v tree &> /dev/null; then
    echo -e "${BLUE}📂 Project structure:${NC}"
    tree -L 2 -I 'node_modules|venv|__pycache__|.git'
fi