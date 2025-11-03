#!/bin/bash

# Tunnel Platform - Automated AWS EC2 Deployment
# Deploys both frontend and backend to a single EC2 instance (Free Tier)

set -e

echo "=========================================="
echo "🚀 AWS EC2 Deployment Wizard"
echo "=========================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
REGION="us-east-1"
INSTANCE_TYPE="t2.micro"  # Free tier
KEY_NAME="tunnel-platform-key"
SECURITY_GROUP="tunnel-platform-sg"
AMI_ID=""  # Will be auto-detected

# Step 1: Check AWS CLI
echo -e "${YELLOW}📋 Step 1: Checking AWS CLI...${NC}"
if ! command -v aws &> /dev/null; then
    echo -e "${RED}❌ AWS CLI not found${NC}"
    echo "Install with: pip install awscli"
    exit 1
fi

# Test credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}❌ AWS credentials not configured${NC}"
    echo "Run: aws configure"
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo -e "${GREEN}✅ AWS Account: $ACCOUNT_ID${NC}"
echo ""

# Step 2: Get latest Ubuntu AMI
echo -e "${YELLOW}📋 Step 2: Finding latest Ubuntu AMI...${NC}"
AMI_ID=$(aws ec2 describe-images \
    --owners 099720109477 \
    --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
    --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
    --region $REGION \
    --output text)

if [ -z "$AMI_ID" ]; then
    echo -e "${RED}❌ Failed to find Ubuntu AMI${NC}"
    exit 1
fi
echo -e "${GREEN}✅ AMI: $AMI_ID${NC}"
echo ""

# Step 3: Create/Check SSH Key
echo -e "${YELLOW}📋 Step 3: Setting up SSH key...${NC}"
if [ ! -f "$HOME/.ssh/$KEY_NAME.pem" ]; then
    echo "Creating new SSH key pair..."
    aws ec2 create-key-pair \
        --key-name $KEY_NAME \
        --region $REGION \
        --query 'KeyMaterial' \
        --output text > $HOME/.ssh/$KEY_NAME.pem
    chmod 400 $HOME/.ssh/$KEY_NAME.pem
    echo -e "${GREEN}✅ SSH key created: $HOME/.ssh/$KEY_NAME.pem${NC}"
else
    echo -e "${GREEN}✅ SSH key exists${NC}"
fi
echo ""

# Step 4: Create/Check Security Group
echo -e "${YELLOW}📋 Step 4: Setting up security group...${NC}"
SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=$SECURITY_GROUP" \
    --region $REGION \
    --query 'SecurityGroups[0].GroupId' \
    --output text 2>/dev/null)

if [ "$SG_ID" = "None" ] || [ -z "$SG_ID" ]; then
    echo "Creating security group..."
    SG_ID=$(aws ec2 create-security-group \
        --group-name $SECURITY_GROUP \
        --description "Tunnel Platform Security Group" \
        --region $REGION \
        --query 'GroupId' \
        --output text)
    
    # Allow SSH
    aws ec2 authorize-security-group-ingress \
        --group-id $SG_ID \
        --protocol tcp \
        --port 22 \
        --cidr 0.0.0.0/0 \
        --region $REGION
    
    # Allow HTTP
    aws ec2 authorize-security-group-ingress \
        --group-id $SG_ID \
        --protocol tcp \
        --port 80 \
        --cidr 0.0.0.0/0 \
        --region $REGION
    
    # Allow HTTPS
    aws ec2 authorize-security-group-ingress \
        --group-id $SG_ID \
        --protocol tcp \
        --port 443 \
        --cidr 0.0.0.0/0 \
        --region $REGION
    
    echo -e "${GREEN}✅ Security group created: $SG_ID${NC}"
else
    echo -e "${GREEN}✅ Security group exists: $SG_ID${NC}"
fi
echo ""

# Step 5: Build frontend
echo -e "${YELLOW}📋 Step 5: Building frontend...${NC}"
cd frontend
npm install
npm run build
cd ..
echo -e "${GREEN}✅ Frontend built${NC}"
echo ""

# Step 6: Create deployment package
echo -e "${YELLOW}📋 Step 6: Creating deployment package...${NC}"
mkdir -p deploy
cp -r backend/* deploy/
cp -r frontend/dist deploy/frontend-dist
cd deploy

# Create deployment script
cat > deploy_script.sh << 'DEPLOY_EOF'
#!/bin/bash
set -e

echo "🚀 Installing dependencies..."
sudo apt-get update
sudo apt-get install -y python3-pip python3-venv nginx

echo "📦 Setting up backend..."
cd /home/ubuntu/app
python3 -m venv venv
source venv/bin/activate
pip install fastapi uvicorn sqlalchemy python-jose[cryptography] passlib[argon2] python-multipart boto3 qrcode pillow python-dotenv pydantic[email] argon2-cffi

echo "🔧 Configuring systemd service..."
sudo tee /etc/systemd/system/tunnel-platform.service > /dev/null << 'SERVICE'
[Unit]
Description=Tunnel Platform Backend
After=network.target

[Service]
User=ubuntu
WorkingDirectory=/home/ubuntu/app
Environment="PATH=/home/ubuntu/app/venv/bin"
ExecStart=/home/ubuntu/app/venv/bin/python app.py
Restart=always

[Install]
WantedBy=multi-user.target
SERVICE

echo "🌐 Configuring Nginx..."
sudo tee /etc/nginx/sites-available/tunnel-platform > /dev/null << 'NGINX'
server {
    listen 80;
    server_name _;

    # Frontend
    location / {
        root /home/ubuntu/app/frontend-dist;
        try_files $uri $uri/ /index.html;
    }

    # Backend API
    location /api {
        proxy_pass http://localhost:8000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
NGINX

sudo ln -sf /etc/nginx/sites-available/tunnel-platform /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl restart nginx

echo "🚀 Starting backend..."
sudo systemctl daemon-reload
sudo systemctl enable tunnel-platform
sudo systemctl start tunnel-platform

echo "✅ Deployment complete!"
echo "🌐 Application available at: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"
DEPLOY_EOF

chmod +x deploy_script.sh
cd ..

# Create tarball
tar -czf deploy.tar.gz -C deploy .
echo -e "${GREEN}✅ Package created: deploy.tar.gz${NC}"
echo ""

# Step 7: Launch EC2 instance
echo -e "${YELLOW}📋 Step 7: Launching EC2 instance...${NC}"
echo "Instance type: $INSTANCE_TYPE (Free Tier)"
echo ""

INSTANCE_ID=$(aws ec2 run-instances \
    --image-id $AMI_ID \
    --instance-type $INSTANCE_TYPE \
    --key-name $KEY_NAME \
    --security-group-ids $SG_ID \
    --region $REGION \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=Tunnel-Platform}]" \
    --query 'Instances[0].InstanceId' \
    --output text)

echo -e "${GREEN}✅ Instance launched: $INSTANCE_ID${NC}"
echo ""

# Wait for instance to be running
echo -e "${YELLOW}⏳ Waiting for instance to start...${NC}"
aws ec2 wait instance-running --instance-ids $INSTANCE_ID --region $REGION

# Get public IP
PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-ids $INSTANCE_ID \
    --region $REGION \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)

echo -e "${GREEN}✅ Instance running at: $PUBLIC_IP${NC}"
echo ""

# Wait for SSH to be ready
echo -e "${YELLOW}⏳ Waiting for SSH to be ready...${NC}"
sleep 30

for i in {1..10}; do
    if ssh -i $HOME/.ssh/$KEY_NAME.pem -o StrictHostKeyChecking=no ubuntu@$PUBLIC_IP "echo SSH ready" &>/dev/null; then
        break
    fi
    echo "Attempt $i/10..."
    sleep 10
done

echo -e "${GREEN}✅ SSH ready${NC}"
echo ""

# Step 8: Upload and deploy
echo -e "${YELLOW}📋 Step 8: Uploading application...${NC}"
scp -i $HOME/.ssh/$KEY_NAME.pem -o StrictHostKeyChecking=no deploy.tar.gz ubuntu@$PUBLIC_IP:/home/ubuntu/
echo ""

echo -e "${YELLOW}📋 Step 9: Installing on server...${NC}"
ssh -i $HOME/.ssh/$KEY_NAME.pem -o StrictHostKeyChecking=no ubuntu@$PUBLIC_IP << 'REMOTE_COMMANDS'
cd /home/ubuntu
tar -xzf deploy.tar.gz -C app
cd app
chmod +x deploy_script.sh
./deploy_script.sh
REMOTE_COMMANDS

echo ""
echo -e "${GREEN}=========================================="
echo "🎉 Deployment Complete!"
echo "==========================================${NC}"
echo ""
echo -e "${BLUE}📍 Application URL: http://$PUBLIC_IP${NC}"
echo -e "${BLUE}🔑 SSH Access: ssh -i $HOME/.ssh/$KEY_NAME.pem ubuntu@$PUBLIC_IP${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Visit http://$PUBLIC_IP"
echo "2. Create an account"
echo "3. Configure your .env on server with AWS credentials:"
echo "   ssh -i $HOME/.ssh/$KEY_NAME.pem ubuntu@$PUBLIC_IP"
echo "   nano /home/ubuntu/app/.env"
echo "   sudo systemctl restart tunnel-platform"
echo ""
echo -e "${YELLOW}To update later:${NC}"
echo "./deploy-aws.sh update $PUBLIC_IP"
echo ""
echo -e "${GREEN}💰 Cost: FREE (first 12 months with AWS Free Tier)${NC}"
echo "=========================================="

# Save instance info
cat > deployment-info.txt << EOF
Deployment Information
=====================
Instance ID: $INSTANCE_ID
Public IP: $PUBLIC_IP
Region: $REGION
SSH Key: $HOME/.ssh/$KEY_NAME.pem
Security Group: $SG_ID

SSH Command:
ssh -i $HOME/.ssh/$KEY_NAME.pem ubuntu@$PUBLIC_IP

Application URL:
http://$PUBLIC_IP

To stop instance:
aws ec2 stop-instances --instance-ids $INSTANCE_ID --region $REGION

To terminate instance:
aws ec2 terminate-instances --instance-ids $INSTANCE_ID --region $REGION

To view logs:
ssh -i $HOME/.ssh/$KEY_NAME.pem ubuntu@$PUBLIC_IP
sudo journalctl -u tunnel-platform -f
EOF

echo "📄 Instance details saved to: deployment-info.txt"