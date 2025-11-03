#!/bin/bash

# Tunnel Platform - Universal Deployment Script
# Choose your deployment platform with 100% automation

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

clear
echo -e "${CYAN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║     🚀 TUNNEL PLATFORM DEPLOYMENT WIZARD 🚀              ║
║                                                           ║
║          Deploy to ANY platform in minutes!              ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

echo ""
echo -e "${YELLOW}Choose your deployment platform:${NC}"
echo ""
echo -e "${GREEN}1)${NC} AWS EC2 (Recommended)"
echo -e "   ${BLUE}→${NC} FREE for 12 months"
echo -e "   ${BLUE}→${NC} Full control, best performance"
echo -e "   ${BLUE}→${NC} t2.micro instance"
echo -e "   ${BLUE}→${NC} Requires: AWS account"
echo ""
echo -e "${GREEN}2)${NC} Railway.app"
echo -e "   ${BLUE}→${NC} \$5/month free credit"
echo -e "   ${BLUE}→${NC} Easiest deployment"
echo -e "   ${BLUE}→${NC} Auto HTTPS + PostgreSQL"
echo -e "   ${BLUE}→${NC} Requires: Credit card"
echo ""
echo -e "${GREEN}3)${NC} Render.com"
echo -e "   ${BLUE}→${NC} 100% FREE forever"
echo -e "   ${BLUE}→${NC} Auto HTTPS + PostgreSQL"
echo -e "   ${BLUE}→${NC} Sleeps after 15min inactive"
echo -e "   ${BLUE}→${NC} Requires: GitHub account"
echo ""
echo -e "${GREEN}4)${NC} Vercel (Frontend Only)"
echo -e "   ${BLUE}→${NC} 100% FREE"
echo -e "   ${BLUE}→${NC} Best for static frontend"
echo -e "   ${BLUE}→${NC} Use with Railway/Render backend"
echo ""
echo -e "${GREEN}5)${NC} View Comparison Table"
echo ""
echo -e "${GREEN}6)${NC} Exit"
echo ""
read -p "$(echo -e ${YELLOW}Enter your choice [1-6]: ${NC})" choice

case $choice in
    1)
        # AWS EC2 Deployment
        clear
        echo -e "${CYAN}═══════════════════════════════════════${NC}"
        echo -e "${GREEN}     AWS EC2 DEPLOYMENT${NC}"
        echo -e "${CYAN}═══════════════════════════════════════${NC}"
        echo ""
        
        # Check AWS CLI
        if ! command -v aws &> /dev/null; then
            echo -e "${RED}❌ AWS CLI not found${NC}"
            echo ""
            echo "Install AWS CLI:"
            echo "  macOS:   brew install awscli"
            echo "  Linux:   pip install awscli"
            echo "  Windows: Download from aws.amazon.com/cli"
            echo ""
            exit 1
        fi
        
        # Check AWS credentials
        if ! aws sts get-caller-identity &> /dev/null; then
            echo -e "${RED}❌ AWS credentials not configured${NC}"
            echo ""
            echo "Configure AWS:"
            echo "  aws configure"
            echo ""
            echo "You'll need:"
            echo "  • AWS Access Key ID"
            echo "  • AWS Secret Access Key"
            echo "  • Default region (e.g., us-east-1)"
            echo ""
            exit 1
        fi
        
        echo -e "${GREEN}✅ AWS CLI configured${NC}"
        echo ""
        echo -e "${YELLOW}This will:${NC}"
        echo "  1. Launch t2.micro EC2 instance (FREE tier)"
        echo "  2. Install Nginx, Python, PostgreSQL"
        echo "  3. Deploy backend + frontend"
        echo "  4. Configure systemd service"
        echo "  5. Set up reverse proxy"
        echo ""
        echo -e "${YELLOW}Estimated time: 10 minutes${NC}"
        echo ""
        read -p "$(echo -e ${YELLOW}Continue? [y/N]: ${NC})" confirm
        
        if [[ $confirm == [yY] ]]; then
            chmod +x deploy-aws.sh
            ./deploy-aws.sh
        fi
        ;;
        
    2)
        # Railway Deployment
        clear
        echo -e "${CYAN}═══════════════════════════════════════${NC}"
        echo -e "${GREEN}     RAILWAY.APP DEPLOYMENT${NC}"
        echo -e "${CYAN}═══════════════════════════════════════${NC}"
        echo ""
        
        # Check Railway CLI
        if ! command -v railway &> /dev/null; then
            echo -e "${YELLOW}📦 Installing Railway CLI...${NC}"
            npm install -g @railway/cli
        fi
        
        echo -e "${GREEN}✅ Railway CLI installed${NC}"
        echo ""
        echo -e "${YELLOW}Follow these steps:${NC}"
        echo ""
        echo -e "${BLUE}1. Login to Railway:${NC}"
        echo "   railway login"
        echo ""
        echo -e "${BLUE}2. Create new project:${NC}"
        echo "   railway init"
        echo ""
        echo -e "${BLUE}3. Add PostgreSQL:${NC}"
        echo "   railway add"
        echo "   Select: PostgreSQL"
        echo ""
        echo -e "${BLUE}4. Set environment variables:${NC}"
        echo "   railway variables set SECRET_KEY=\$(openssl rand -hex 32)"
        echo "   railway variables set AWS_ACCESS_KEY_ID=your_key"
        echo "   railway variables set AWS_SECRET_ACCESS_KEY=your_secret"
        echo ""
        echo -e "${BLUE}5. Deploy:${NC}"
        echo "   railway up"
        echo ""
        echo -e "${BLUE}6. Get your URL:${NC}"
        echo "   railway domain"
        echo ""
        read -p "$(echo -e ${YELLOW}Press Enter to open Railway documentation...${NC})"
        
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://docs.railway.app/getting-started"
        elif command -v open &> /dev/null; then
            open "https://docs.railway.app/getting-started"
        fi
        ;;
        
    3)
        # Render Deployment
        clear
        echo -e "${CYAN}═══════════════════════════════════════${NC}"
        echo -e "${GREEN}     RENDER.COM DEPLOYMENT${NC}"
        echo -e "${CYAN}═══════════════════════════════════════${NC}"
        echo ""
        
        echo -e "${YELLOW}Option 1: GitHub (Recommended)${NC}"
        echo ""
        echo "1. Push code to GitHub:"
        echo "   git init"
        echo "   git add ."
        echo "   git commit -m 'Initial commit'"
        echo "   git remote add origin YOUR_GITHUB_URL"
        echo "   git push -u origin main"
        echo ""
        echo "2. Go to render.com and click 'New' → 'Blueprint'"
        echo "3. Connect your GitHub repository"
        echo "4. Render auto-detects render.yaml and deploys!"
        echo ""
        echo -e "${YELLOW}Option 2: Manual${NC}"
        echo ""
        echo "1. Go to render.com"
        echo "2. Click 'New' → 'Web Service'"
        echo "3. Upload code or connect GitHub"
        echo "4. Follow on-screen instructions"
        echo ""
        echo -e "${GREEN}✅ Your render.yaml is already configured!${NC}"
        echo ""
        read -p "$(echo -e ${YELLOW}Open Render.com now? [y/N]: ${NC})" open_render
        
        if [[ $open_render == [yY] ]]; then
            if command -v xdg-open &> /dev/null; then
                xdg-open "https://render.com"
            elif command -v open &> /dev/null; then
                open "https://render.com"
            fi
        fi
        ;;
        
    4)
        # Vercel (Frontend Only)
        clear
        echo -e "${CYAN}═══════════════════════════════════════${NC}"
        echo -e "${GREEN}     VERCEL DEPLOYMENT (FRONTEND)${NC}"
        echo -e "${CYAN}═══════════════════════════════════════${NC}"
        echo ""
        
        # Check Vercel CLI
        if ! command -v vercel &> /dev/null; then
            echo -e "${YELLOW}📦 Installing Vercel CLI...${NC}"
            npm install -g vercel
        fi
        
        echo -e "${GREEN}✅ Vercel CLI installed${NC}"
        echo ""
        echo -e "${YELLOW}Deploy frontend to Vercel:${NC}"
        echo ""
        echo "1. Build frontend:"
        echo "   cd frontend"
        echo "   npm run build"
        echo ""
        echo "2. Deploy:"
        echo "   vercel --prod"
        echo ""
        echo -e "${YELLOW}⚠️  Note: You still need to deploy backend separately!${NC}"
        echo "   Use Railway or Render for backend"
        echo ""
        read -p "$(echo -e ${YELLOW}Deploy now? [y/N]: ${NC})" deploy_vercel
        
        if [[ $deploy_vercel == [yY] ]]; then
            cd frontend
            npm run build
            vercel --prod
            cd ..
        fi
        ;;
        
    5)
        # Comparison Table
        clear
        echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}                    PLATFORM COMPARISON                             ${NC}"
        echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
        echo ""
        printf "%-15s %-15s %-15s %-15s %-15s\n" "Platform" "Cost" "Setup" "HTTPS" "Database"
        echo "─────────────────────────────────────────────────────────────────────"
        printf "%-15s %-15s %-15s %-15s %-15s\n" "AWS EC2" "FREE (1yr)" "10 min" "Manual" "SQLite"
        printf "%-15s %-15s %-15s %-15s %-15s\n" "Railway" "\$5/mo credit" "5 min" "Auto" "PostgreSQL"
        printf "%-15s %-15s %-15s %-15s %-15s\n" "Render" "FREE forever" "3 min" "Auto" "PostgreSQL"
        printf "%-15s %-15s %-15s %-15s %-15s\n" "Vercel" "FREE" "2 min" "Auto" "None*"
        echo ""
        echo -e "${YELLOW}* Vercel is frontend-only. Use with Railway/Render backend.${NC}"
        echo ""
        echo -e "${GREEN}Recommendation:${NC}"
        echo "  • Production: AWS EC2"
        echo "  • Quick start: Railway"
        echo "  • Demo/Free: Render"
        echo ""
        read -p "$(echo -e ${YELLOW}Press Enter to return to menu...${NC})"
        $0  # Restart script
        ;;
        
    6)
        echo -e "${GREEN}Goodbye! 👋${NC}"
        exit 0
        ;;
        
    *)
        echo -e "${RED}Invalid choice${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN}    Deployment script completed!${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}Need help?${NC}"
echo "  • Check DEPLOYMENT.md for detailed guides"
echo "  • Check TROUBLESHOOTING.md for common issues"
echo "  • Open an issue on GitHub"
echo ""
echo -e "${CYAN}Happy deploying! 🚀${NC}"