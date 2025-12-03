#!/bin/bash
# Push to GitHub: https://github.com/KSD-CO/rule-engine-postgres

set -e

echo "🚀 Pushing to GitHub: KSD-CO/rule-engine-postgres"
echo ""

# Initialize git if not exists
if [ ! -d ".git" ]; then
    echo "Initializing git repository..."
    git init
    git branch -M main
fi

# Add remote
if ! git remote | grep -q origin; then
    echo "Adding remote origin..."
    git remote add origin https://github.com/KSD-CO/rule-engine-postgres.git
else
    echo "Setting remote origin URL..."
    git remote set-url origin https://github.com/KSD-CO/rule-engine-postgres.git
fi

# Create .gitignore if not exists
if [ ! -f ".gitignore" ]; then
    cat > .gitignore << 'EOF'
# Rust
/target/
**/*.rs.bk
*.pdb

# IDE
.idea/
.vscode/
*.swp
*.swo
*~
.DS_Store

# pgrx
.pgx/
.pgrx/

# Build artifacts
*.so
*.dylib
*.dll
*.bc
*.o

# Logs
*.log

# Environment
.env
.env.local

# Temp
/tmp/
*.deb
EOF
fi

# Add all files
echo "Staging files..."
git add .

# Check if there are changes to commit
if git diff --cached --quiet; then
    echo "No changes to commit"
else
    # Commit
    echo "Creating commit..."
    git commit -m "feat: Production-ready PostgreSQL rule engine extension v1.0.0

- Health check and version functions
- Structured error codes (ERR001-ERR012)
- Docker support with multi-stage builds
- CI/CD pipeline with GitHub Actions
- Distribution support (PGXN, .deb, Docker Hub)
- Complete documentation and deployment guides
- rust-rule-engine 0.14.1
- Supports PostgreSQL 13-17"
fi

# Show current status
echo ""
echo "📋 Git Status:"
git status

echo ""
echo "📦 Remote:"
git remote -v

echo ""
echo "✅ Ready to push!"
echo ""
echo "To push to GitHub, run:"
echo "  git push -u origin main"
echo ""
echo "If this is the first push to a new repo:"
echo "  git push -u origin main --force  # Use with caution!"
echo ""
echo "After pushing, create a release:"
echo "  git tag v1.0.0"
echo "  git push origin v1.0.0"
