@echo off
REM Tunnel Platform - Windows One-Click AWS Deployment
REM Uses credentials from .env file

setlocal enabledelayedexpansion

echo ==========================================
echo 🚀 AWS EC2 Deployment for Windows
echo ==========================================
echo.

REM Check if in backend directory
if not exist "app.py" (
    echo ❌ Error: Run this script from the backend directory
    pause
    exit /b 1
)

REM Load .env file and set AWS credentials
echo 📋 Loading AWS credentials from .env...
for /f "usebackq tokens=1,2 delims==" %%a in ("..\.env") do (
    if "%%a"=="AWS_ACCESS_KEY_ID" set AWS_ACCESS_KEY_ID=%%b
    if "%%a"=="AWS_SECRET_ACCESS_KEY" set AWS_SECRET_ACCESS_KEY=%%b
    if "%%a"=="AWS_REGION" set AWS_REGION=%%b
)

if "%AWS_ACCESS_KEY_ID%"=="" (
    echo ❌ AWS_ACCESS_KEY_ID not found in .env
    pause
    exit /b 1
)

if "%AWS_SECRET_ACCESS_KEY%"=="" (
    echo ❌ AWS_SECRET_ACCESS_KEY not found in .env
    pause
    exit /b 1
)

if "%AWS_REGION%"=="" set AWS_REGION=us-east-1

echo ✅ AWS Credentials loaded
echo    Region: %AWS_REGION%
echo    Key ID: %AWS_ACCESS_KEY_ID:~0,8%...
echo.

REM Check AWS CLI
aws --version >nul 2>&1
if errorlevel 1 (
    echo ❌ AWS CLI not installed
    echo.
    echo Install AWS CLI:
    echo   1. Download: https://awscli.amazonaws.com/AWSCLIV2.msi
    echo   2. Run installer
    echo   3. Restart terminal
    echo.
    pause
    exit /b 1
)

echo ✅ AWS CLI installed
echo.

REM Export AWS credentials for this session
set AWS_DEFAULT_REGION=%AWS_REGION%

REM Test AWS credentials
echo 📋 Testing AWS connection...
aws sts get-caller-identity --region %AWS_REGION% >nul 2>&1
if errorlevel 1 (
    echo ❌ AWS credentials invalid
    echo.
    echo Please check your .env file:
    echo   AWS_ACCESS_KEY_ID
    echo   AWS_SECRET_ACCESS_KEY
    echo.
    pause
    exit /b 1
)

for /f "tokens=*" %%i in ('aws sts get-caller-identity --query Account --output text --region %AWS_REGION%') do set ACCOUNT_ID=%%i
echo ✅ AWS Account: %ACCOUNT_ID%
echo.

REM Configuration
set KEY_NAME=tunnel-platform-key
set SECURITY_GROUP=tunnel-platform-sg
set INSTANCE_TYPE=t2.micro

REM Get Ubuntu AMI
echo 📋 Finding latest Ubuntu AMI...
for /f "tokens=*" %%i in ('aws ec2 describe-images --owners 099720109477 --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" --query "Images | sort_by(@, &CreationDate) | [-1].ImageId" --region %AWS_REGION% --output text') do set AMI_ID=%%i

if "%AMI_ID%"=="" (
    echo ❌ Failed to find Ubuntu AMI
    pause
    exit /b 1
)

echo ✅ AMI: %AMI_ID%
echo.

REM Create SSH key pair
echo 📋 Setting up SSH key...
if not exist "%USERPROFILE%\.ssh\%KEY_NAME%.pem" (
    echo Creating new SSH key pair...
    aws ec2 create-key-pair --key-name %KEY_NAME% --region %AWS_REGION% --query "KeyMaterial" --output text > "%USERPROFILE%\.ssh\%KEY_NAME%.pem"
    echo ✅ SSH key created
) else (
    echo ✅ SSH key exists
)
echo.

REM Get or create security group
echo 📋 Setting up security group...
for /f "tokens=*" %%i in ('aws ec2 describe-security-groups --filters "Name=group-name,Values=%SECURITY_GROUP%" --region %AWS_REGION% --query "SecurityGroups[0].GroupId" --output text 2^>nul') do set SG_ID=%%i

if "%SG_ID%"=="None" set SG_ID=
if "%SG_ID%"=="" (
    echo Creating security group...
    for /f "tokens=*" %%i in ('aws ec2 create-security-group --group-name %SECURITY_GROUP% --description "Tunnel Platform" --region %AWS_REGION% --query GroupId --output text') do set SG_ID=%%i
    
    REM Allow SSH
    aws ec2 authorize-security-group-ingress --group-id %SG_ID% --protocol tcp --port 22 --cidr 0.0.0.0/0 --region %AWS_REGION% >nul
    
    REM Allow HTTP
    aws ec2 authorize-security-group-ingress --group-id %SG_ID% --protocol tcp --port 80 --cidr 0.0.0.0/0 --region %AWS_REGION% >nul
    
    REM Allow HTTPS
    aws ec2 authorize-security-group-ingress --group-id %SG_ID% --protocol tcp --port 443 --cidr 0.0.0.0/0 --region %AWS_REGION% >nul
    
    echo ✅ Security group created: %SG_ID%
) else (
    echo ✅ Security group exists: %SG_ID%
)
echo.

REM Build frontend
echo 📋 Building frontend...
cd ..\frontend
if not exist "node_modules" (
    echo Installing npm packages...
    call npm install
)
call npm run build
cd ..\backend
echo ✅ Frontend built
echo.

REM Create user data script
echo 📋 Creating deployment package...
(
echo #!/bin/bash
echo set -e
echo echo "Installing dependencies..."
echo apt-get update
echo apt-get install -y python3-pip python3-venv nginx
echo echo "Setting up application..."
echo cd /home/ubuntu
echo mkdir -p app
echo cd app
echo python3 -m venv venv
echo source venv/bin/activate
echo pip install fastapi uvicorn sqlalchemy python-jose[cryptography] passlib[argon2] python-multipart boto3 qrcode pillow python-dotenv pydantic[email] argon2-cffi
echo echo "Creating systemd service..."
echo cat ^> /etc/systemd/system/tunnel-platform.service ^<^< 'SERVICE'
echo [Unit]
echo Description=Tunnel Platform
echo After=network.target
echo [Service]
echo User=ubuntu
echo WorkingDirectory=/home/ubuntu/app
echo Environment="PATH=/home/ubuntu/app/venv/bin"
echo ExecStart=/home/ubuntu/app/venv/bin/python app.py
echo Restart=always
echo [Install]
echo WantedBy=multi-user.target
echo SERVICE
echo systemctl daemon-reload
echo systemctl enable tunnel-platform
echo echo "Configuring Nginx..."
echo cat ^> /etc/nginx/sites-available/tunnel-platform ^<^< 'NGINX'
echo server {
echo     listen 80;
echo     server_name _;
echo     location / {
echo         root /home/ubuntu/app/frontend-dist;
echo         try_files $uri $uri/ /index.html;
echo     }
echo     location /api {
echo         proxy_pass http://localhost:8000;
echo         proxy_set_header Host $host;
echo         proxy_set_header X-Real-IP $remote_addr;
echo     }
echo }
echo NGINX
echo ln -sf /etc/nginx/sites-available/tunnel-platform /etc/nginx/sites-enabled/
echo rm -f /etc/nginx/sites-enabled/default
echo nginx -t
echo systemctl restart nginx
echo echo "Deployment complete!"
) > userdata.sh

echo ✅ Deployment script created
echo.

REM Launch instance
echo 📋 Launching EC2 instance...
echo Instance type: %INSTANCE_TYPE% (Free Tier)
echo.

for /f "tokens=*" %%i in ('aws ec2 run-instances --image-id %AMI_ID% --instance-type %INSTANCE_TYPE% --key-name %KEY_NAME% --security-group-ids %SG_ID% --user-data file://userdata.sh --region %AWS_REGION% --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=Tunnel-Platform}]" --query "Instances[0].InstanceId" --output text') do set INSTANCE_ID=%%i

echo ✅ Instance launched: %INSTANCE_ID%
echo.

REM Wait for instance
echo ⏳ Waiting for instance to start (this takes 2-3 minutes)...
aws ec2 wait instance-running --instance-ids %INSTANCE_ID% --region %AWS_REGION%

REM Get public IP
for /f "tokens=*" %%i in ('aws ec2 describe-instances --instance-ids %INSTANCE_ID% --region %AWS_REGION% --query "Reservations[0].Instances[0].PublicIpAddress" --output text') do set PUBLIC_IP=%%i

echo ✅ Instance running at: %PUBLIC_IP%
echo.

REM Wait for SSH
echo ⏳ Waiting for SSH to be ready...
timeout /t 30 /nobreak >nul

echo.
echo ==========================================
echo 🎉 Deployment Complete!
echo ==========================================
echo.
echo 📍 Application URL: http://%PUBLIC_IP%
echo 🔑 SSH Command: ssh -i "%USERPROFILE%\.ssh\%KEY_NAME%.pem" ubuntu@%PUBLIC_IP%
echo.
echo ⚠️  IMPORTANT: Configure environment on server:
echo.
echo 1. SSH into server:
echo    ssh -i "%USERPROFILE%\.ssh\%KEY_NAME%.pem" ubuntu@%PUBLIC_IP%
echo.
echo 2. Create .env file:
echo    nano /home/ubuntu/app/.env
echo.
echo 3. Add these variables:
echo    SECRET_KEY=%SECRET_KEY%
echo    AWS_ACCESS_KEY_ID=%AWS_ACCESS_KEY_ID%
echo    AWS_SECRET_ACCESS_KEY=%AWS_SECRET_ACCESS_KEY%
echo    DATABASE_URL=sqlite:///./tunnel_platform.db
echo.
echo 4. Upload files and start:
echo    (Files will be uploaded separately)
echo.
echo 💰 Cost: FREE for 12 months with AWS Free Tier
echo.
echo Instance ID: %INSTANCE_ID%
echo Region: %AWS_REGION%
echo.
echo To stop instance:
echo aws ec2 stop-instances --instance-ids %INSTANCE_ID% --region %AWS_REGION%
echo.
echo To terminate instance:
echo aws ec2 terminate-instances --instance-ids %INSTANCE_ID% --region %AWS_REGION%
echo.
echo ==========================================

REM Save deployment info
(
echo Deployment Information
echo =====================
echo Instance ID: %INSTANCE_ID%
echo Public IP: %PUBLIC_IP%
echo Region: %AWS_REGION%
echo SSH Key: %USERPROFILE%\.ssh\%KEY_NAME%.pem
echo Security Group: %SG_ID%
echo.
echo SSH Command:
echo ssh -i "%USERPROFILE%\.ssh\%KEY_NAME%.pem" ubuntu@%PUBLIC_IP%
echo.
echo Application URL:
echo http://%PUBLIC_IP%
) > deployment-info.txt

echo 📄 Deployment info saved to: deployment-info.txt
echo.
pause