# Distribution Guide

How to distribute and publish `rule-engine-postgres` for easy installation.

## 📦 Distribution Methods

### 1. PGXN (PostgreSQL Extension Network)

**PGXN** is the official package manager for PostgreSQL extensions (like npm for Node.js).

#### Publish to PGXN

```bash
# 1. Create account at https://manager.pgxn.org/

# 2. Validate META.json
pgxn validate META.json

# 3. Bundle extension
make clean
pgxn bundle

# 4. Upload to PGXN
pgxn release rule_engine_postgre_extensions-1.0.0.zip
docker build -t jamesvu/rule-engine-postgres:1.0.0 .

#### Users Install from PGXN
docker tag jamesvu/rule-engine-postgres:1.0.0 jamesvu/rule-engine-postgres:latest
```bash
# Install pgxn client
docker push jamesvu/rule-engine-postgres:1.0.0

docker push jamesvu/rule-engine-postgres:latest
# Install extension
pgxn install rule_engine_postgre_extensions
docker pull jamesvu/rule-engine-postgres:1.0.0

docker run -d -p 5432:5432 jamesvu/rule-engine-postgres:1.0.0
# Enable in PostgreSQL
psql -d mydb -c "CREATE EXTENSION rule_engine_postgre_extensions;"
```

---

### 2. Pre-built Binary Packages
    image: jamesvu/rule-engine-postgres:1.0.0
#### Build .deb Package (Debian/Ubuntu)

```bash
# Build package
# Output: postgresql-16-rule-engine_1.0.0_amd64.deb
#### Distribute via GitHub Releases
```bash
# Build image
docker build -t jamesvu/rule-engine-postgres:1.0.0 .

# Tag as latest
docker tag jamesvu/rule-engine-postgres:1.0.0 jamesvu/rule-engine-postgres:latest

# Push to Docker Hub
docker push jamesvu/rule-engine-postgres:1.0.0
docker push jamesvu/rule-engine-postgres:latest

**Users install**:

```bash
# Pull and run
License:        MIT
URL:            https://github.com/KSD-CO/rule-engine-postgres
```

Or via docker-compose:

```yaml
services:
  postgres:
    image: jamesvu/rule-engine-postgres:1.0.0
    environment:
      POSTGRES_PASSWORD: postgres
```
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  postgresql16-devel
BuildRequires:  cargo
BuildRequires:  rust >= 1.75

%description
docker build -t jamesvu/rule-engine-postgres:1.1.0 .

%build
cargo build --release --features pg16

%install
docker push jamesvu/rule-engine-postgres:1.1.0
mkdir -p %{buildroot}/usr/pgsql-16/share/extension
cp target/release/librule_engine_postgre_extensions.so %{buildroot}/usr/pgsql-16/lib/
cp *.control %{buildroot}/usr/pgsql-16/share/extension/
cp *.sql %{buildroot}/usr/pgsql-16/share/extension/

%files
/usr/pgsql-16/lib/rule_engine_postgre_extensions.so
/usr/pgsql-16/share/extension/*
```

Build RPM:
```bash
rpmbuild -ba rule-engine.spec
```

---

### 3. Docker Hub

**Publish Docker image**:

```bash
# Build image
docker tag jamesvu/rule-engine-postgres:1.0.0 jamesvu/rule-engine-postgres:latest
docker build -t jamesvu/rule-engine-postgres:1.0.0 .

# Tag as latest
docker tag jamesvu/rule-engine-postgres:1.0.0 jamesvu/rule-engine-postgres:latest

# Push to Docker Hub

docker pull jamesvu/rule-engine-postgres:1.0.0

Or via docker-compose:

```
docker build -t jamesvu/rule-engine-postgres:1.0.0 .
### 3. Docker Hub

We publish Docker images to Docker Hub. The GitHub Actions `release` workflow now pushes images to Docker Hub using repository secrets.
docker push jamesvu/rule-engine-postgres:1.1.0
Local publish example:

```bash
# Build image
# Generate Packages file

# Tag as latest
cd apt-repo

# Push to Docker Hub
dpkg-scanpackages pool /dev/null | gzip -9c > dists/stable/main/binary-amd64/Packages.gz

# Upload to server (e.g., GitHub Pages, S3, etc.)
```

CI / GitHub Actions notes

- The release workflow (`.github/workflows/release.yml`) builds and pushes images to Docker Hub.
- You must set the following repository secrets in GitHub for the push step to work:
  - `DOCKERHUB_USERNAME` — Docker Hub username or organization name
  - `DOCKERHUB_TOKEN` — Docker Hub personal access token (recommended) or password

**Users install**:

```bash
# Pull and run
```

```

Or via docker-compose:

```yaml
services:
  postgres:
  image: jamesvu/rule-engine-postgres:1.0.0
    environment:
      POSTGRES_PASSWORD: postgres
```
**Users add repository**:

```bash
# Add repository
echo "deb https://KSD-CO.github.io/apt-repo stable main" | sudo tee /etc/apt/sources.list.d/rule-engine.list

# Install
sudo apt-get update
sudo apt-get install postgresql-16-rule-engine
```

---

### 5. Homebrew (macOS)

Create Homebrew formula:

```ruby
# Formula/rule-engine-postgres.rb
class RuleEnginePostgreExtensions < Formula
  desc "PostgreSQL extension for rule engine with GRL syntax"
  homepage "https://github.com/KSD-CO/rule-engine-postgres"
  url "https://github.com/KSD-CO/rule-engine-postgres/archive/v1.0.0.tar.gz"
  sha256 "REPLACE_WITH_ACTUAL_SHA256"
  license "MIT"

  depends_on "rust" => :build
  depends_on "postgresql@16"

  def install
    system "cargo", "install", *std_cargo_args
    system "cargo", "pgrx", "install", "--pg-config", "#{Formula["postgresql@16"].opt_bin}/pg_config"
  end

  test do
    system "psql", "-c", "CREATE EXTENSION rule_engine_postgre_extensions;"
  end
end
```

**Users install**:

```bash
brew install KSD-CO/tap/rule-engine-postgres
```

---

## 🚀 Quick Install Script

The `quick-install.sh` script automates installation:

**Features:**
- Detects OS and PostgreSQL version
- Downloads pre-built binary if available
- Falls back to building from source
- Handles dependencies automatically

**Usage:**

```bash
curl -fsSL https://raw.githubusercontent.com/KSD-CO/rule-engine-postgres/main/quick-install.sh | bash
```

---

## 📋 Distribution Checklist

Before releasing:

- [ ] Update version in `Cargo.toml`
- [ ] Update version in `META.json`
- [ ] Update version in `.control` file
- [ ] Update `CHANGELOG.md`
- [ ] Build and test locally
- [ ] Build .deb package
- [ ] Build RPM package (if supporting RHEL)
- [ ] Build Docker image
- [ ] Create Git tag: `git tag v1.0.0`
- [ ] Push tag: `git push origin v1.0.0`
- [ ] Create GitHub Release with binaries
- [ ] Publish to PGXN
- [ ] Push Docker image to Docker Hub
- [ ] Update documentation
- [ ] Announce release

---

## 🎯 Recommended Distribution Strategy

### For Maximum Reach:

1. **PGXN** (PostgreSQL users)
2. **GitHub Releases** with pre-built .deb/.rpm (Linux users)
3. **Docker Hub** (containerized deployments)
4. **Quick install script** (easy onboarding)

### Priority Order:

1. ✅ GitHub Releases (free, easy)
2. ✅ Docker Hub (free, popular)
3. ✅ PGXN (PostgreSQL standard)
4. 🔄 APT/YUM repos (requires hosting)
5. 🔄 Homebrew (macOS users)

---

## 📊 Installation Analytics

Track downloads via:

- GitHub Releases download counts
- Docker Hub pull statistics
- PGXN download stats
- Custom analytics in install script

---

## 🔧 Maintenance

### Updating Published Packages

When releasing new version:

```bash
# 1. Update version everywhere
./update-version.sh 1.1.0

# 2. Build packages
./build-deb.sh
docker build -t jamesvu/rule-engine-postgres:1.1.0 .

# 3. Publish
git tag v1.1.0
git push origin v1.1.0
pgxn release rule_engine_postgre_extensions-1.1.0.zip
docker push jamesvu/rule-engine-postgres:1.1.0
```

### Support Multiple PostgreSQL Versions

Build packages for each PG version:

```bash
for PG_VERSION in 13 14 15 16 17; do
    cargo build --release --features pg${PG_VERSION}
    ./build-deb.sh ${PG_VERSION}
done
```

---

**Last Updated**: 2025-01-18 | **Version**: 1.0.0
