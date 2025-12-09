#!/bin/bash

# Setup script for creating the eval-report-viewer repository
# Run this script to initialize git and prepare for pushing to remote

set -e

echo "🚀 Setting up eval-report-viewer repository..."
echo ""

# Step 1: Initialize git if not already initialized
if [ ! -d ".git" ]; then
    echo "📦 Initializing Git repository..."
    git init
    echo "✅ Git initialized"
else
    echo "✅ Git repository already initialized"
fi
echo ""

# Step 2: Add all files
echo "📝 Adding files to git..."
git add .
echo "✅ Files added"
echo ""

# Step 3: Create initial commit
echo "💾 Creating initial commit..."
git commit -m "Initial commit: Eval Report Viewer

Features:
- FastAPI web application for viewing evaluation reports from S3
- Support for pagination to show all S3 folders
- Fixed UI layout with proper spacing
- Added help section with instructions and contact info
- Reports open in new browser tabs
- Docker support for easy deployment
- Deployment scripts for AWS ECS
- Comprehensive documentation

Team:
- Evals Team: prathikantamroopesh.bhat@realpage.com
- Manager: Bhawana Mishra (bhawana.mishra@realpage.com)"
echo "✅ Initial commit created"
echo ""

# Step 4: Instructions for adding remote
echo "📋 Next Steps:"
echo ""
echo "1. Create a new repository on GitHub/GitLab/Bitbucket named 'eval-report-viewer'"
echo ""
echo "2. Add the remote repository (replace with your actual URL):"
echo "   git remote add origin git@github.com:your-org/eval-report-viewer.git"
echo "   OR"
echo "   git remote add origin https://github.com/your-org/eval-report-viewer.git"
echo ""
echo "3. Push to the remote repository:"
echo "   git branch -M main"
echo "   git push -u origin main"
echo ""
echo "Example for GitHub:"
echo "   git remote add origin git@github.com:RealPage/eval-report-viewer.git"
echo "   git branch -M main"
echo "   git push -u origin main"
echo ""
echo "✨ Repository setup complete!"
