# CyMyToolbox Build Configuration Review

## Summary
Your multi-stage build approach is excellent! However, there are several critical issues that will cause build failures. This document explains each issue and the fixes applied.

---

## 🔴 Critical Issues Found

### Issue 1: Permission Errors in Final Stage
**Location**: Dockerfile lines 49-84

**Problem**:
```dockerfile
RUN useradd -ms /bin/bash ansible
USER ansible              # ← Switches to non-root user
WORKDIR /home/ansible

# ... later ...

RUN dnf install -y ...    # ← FAILS! dnf requires root
RUN curl -LO ...          # ← FAILS! Can't write to /usr/local/bin
```

**Why it fails**: After `USER ansible`, all subsequent `RUN` commands execute as the non-root `ansible` user, but:
- `dnf install` requires root privileges
- Installing to `/usr/local/bin/` requires root
- Writing to system directories requires root

**Fix**: Perform all installations and system modifications BEFORE switching to non-root user.

---

### Issue 2: Python Packages Not Copied
**Location**: Dockerfile line 53

**Problem**:
```dockerfile
COPY --from=builder /usr/lib/python3.9/site-packages/ /usr/lib/python3.9/site-packages/
```

**Why it fails**: When you run `pip install`, it installs packages to `/usr/local/lib/python3.9/site-packages/`, not `/usr/lib/python3.9/site-packages/`. The copy operation will either copy nothing or copy wrong files.

**Verification**:
```bash
# In builder stage, pip installs here:
/usr/local/lib/python3.9/site-packages/   ← pip packages
/usr/lib64/python3.9/site-packages/       ← system RPM packages
```

**Fix**: Copy from both locations:
```dockerfile
COPY --from=builder /usr/local/lib/python3.9/site-packages/ /usr/local/lib/python3.9/site-packages/
COPY --from=builder /usr/lib64/python3.9/site-packages/ /usr/lib64/python3.9/site-packages/
```

---

### Issue 3: Missing Runtime Dependencies
**Location**: Dockerfile lines 58-65

**Problem**: The final image is missing runtime libraries that Python packages need:
- `mysqlclient` requires `libmariadb.so` → needs `mariadb-connector-c`
- Other packages may need `libxml2`

**Why it fails**: When you try to import mysqlclient:
```python
>>> import MySQLdb
ImportError: libmariadb.so.3: cannot open shared object file: No such file or directory
```

**Fix**: Add runtime dependencies:
```dockerfile
RUN dnf install -y \
    python3 \
    python3-pip \
    mariadb-connector-c \  # ← Provides libmariadb.so
    libxml2 \              # ← Runtime library
    # ... other deps
```

---

### Issue 4: Collections Directory Permissions
**Location**: Dockerfile line 55

**Problem**:
```dockerfile
COPY --from=builder /root/.ansible/collections/ /home/ansible/.ansible/collections/
```

**Why it fails**:
- Destination directory `/home/ansible/.ansible/collections/` doesn't exist yet
- Files copied will be owned by root (from source), not ansible user
- The ansible user won't have write permissions

**Fix**: Create directory first and use `--chown`:
```dockerfile
RUN mkdir -p /home/ansible/.ansible/collections && \
    chown -R ansible:ansible /home/ansible/.ansible

COPY --from=builder --chown=ansible:ansible /root/.ansible/collections/ /home/ansible/.ansible/collections/
```

---

### Issue 5: K9s Installation Path Issue
**Location**: Dockerfile line 78-79

**Problem**:
```dockerfile
RUN curl -sS https://webinstall.dev/k9s@${K9S_VERSION} | bash && \
    install -o root -g root -m 0755 /root/.local/bin/k9s /usr/local/bin/k9s
```

**Why it might fail**:
- The webi installer behavior is inconsistent
- May not install to expected path
- Requires interactive shell setup

**Fix**: Download k9s directly from GitHub releases:
```dockerfile
RUN curl -LO "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_amd64.tar.gz" && \
    tar xzf k9s_Linux_amd64.tar.gz && \
    install -o root -g root -m 0755 k9s /usr/local/bin/k9s && \
    rm k9s_Linux_amd64.tar.gz k9s LICENSE README.md
```

---

### Issue 6: GitLab CI Chicken-and-Egg Problem
**Location**: .gitlab-ci.yml lines 18-29

**Problem**:
```yaml
stages:
  - lint     # ← Runs FIRST
  - build    # ← Runs SECOND

lint:
  image: ${IMAGE_NAME}:latest  # ← Image doesn't exist yet!
```

**Why it fails**: On first pipeline run, the lint stage tries to use `${IMAGE_NAME}:latest`, but this image hasn't been built yet because build comes AFTER lint.

**Error message**:
```
ERROR: Job failed: image pull failed: image not found
```

**Fix**: Reorder stages so build comes first:
```yaml
stages:
  - build    # ← Build image FIRST
  - lint     # ← Then lint using the just-built image
  - deploy

lint:
  image: ${IMAGE_NAME}:${CI_COMMIT_SHORT_SHA}  # ← Use the specific commit SHA
  allow_failure: true  # ← Don't block pipeline on lint issues initially
```

---

## ✅ Complete Fixed Dockerfile

### Key Changes:
1. ✅ All system installations happen BEFORE `USER ansible`
2. ✅ Copy from correct Python package locations
3. ✅ Include runtime dependencies (`mariadb-connector-c`, `libxml2`)
4. ✅ Create directories and set ownership before copying
5. ✅ Use direct GitHub releases for k9s
6. ✅ Use `CMD` instead of `ENTRYPOINT` for flexibility

### Order of Operations:
```
Builder Stage:
1. Install build dependencies
2. Install Python packages
3. Install Ansible and collections

Final Stage:
1. Install runtime dependencies (as root)
2. Install Kubernetes tools (as root)
3. Copy Python packages from builder
4. Create non-root user
5. Set up directories with correct ownership
6. Copy collections with correct ownership
7. Switch to non-root user
8. Set working directory
```

---

## ✅ Complete Fixed .gitlab-ci.yml

### Key Changes:
1. ✅ Stages reordered: build → lint → deploy
2. ✅ Lint uses `${CI_COMMIT_SHORT_SHA}` tag (just built)
3. ✅ Added `allow_failure: true` to lint stage
4. ✅ Added `|| true` to ansible-lint command (don't fail on warnings)

### Why These Changes:
- **Build first**: Creates the image that lint will use
- **Use commit SHA**: More reliable than `:latest` tag
- **Allow failure**: Don't block pipeline while tuning lint rules
- **|| true**: Treat lint warnings as informational initially

---

## 🚀 Testing the Fixes

### 1. Test Locally First
```bash
cd /home/richardevans/Documents/Code/cymycloud/cymytoolbox

# Copy fixed files
cp Dockerfile.fixed Dockerfile
cp .gitlab-ci.yml.fixed .gitlab-ci.yml

# Build locally
docker build -t cymytoolbox:test-fixed .

# Test the image
docker run --rm cymytoolbox:test-fixed ansible --version
docker run --rm cymytoolbox:test-fixed kubectl version --client
docker run --rm cymytoolbox:test-fixed python3 -c "import MySQLdb; print('MySQLdb works!')"
```

### 2. Commit and Push
```bash
git add Dockerfile .gitlab-ci.yml
git commit -m "Fix multi-stage build and CI pipeline order

- Install all system packages before switching to non-root user
- Copy Python packages from correct locations
- Add runtime dependencies (mariadb-connector-c, libxml2)
- Reorder CI stages: build before lint
- Use commit SHA for lint image reference
- Allow lint failures initially"

git push gitlab main
```

### 3. Monitor Pipeline
```
https://tenant-git.orl01.cymycloud.com/cymycloud/cymytoolbox/-/pipelines
```

Expected flow:
1. ✅ Build stage: ~5-10 minutes
2. ✅ Lint stage: ~1 minute (may warn but won't fail)
3. ✅ Deploy stage: ~10 seconds

---

## 📊 Comparison

### Before (Issues):
```
❌ Dockerfile: 6 critical issues
❌ .gitlab-ci.yml: 1 critical issue
❌ Build will fail at stage 2
❌ Pipeline will fail before build
```

### After (Fixed):
```
✅ Dockerfile: All permission issues resolved
✅ .gitlab-ci.yml: Stage ordering corrected
✅ Build should complete successfully
✅ Pipeline will run all stages
```

---

## 🎯 Benefits of Multi-Stage Build

Your multi-stage approach is excellent! Benefits:

1. **Smaller final image**: Build tools not included
2. **Security**: No compilers in production image
3. **Non-root**: Runs as `ansible` user (security best practice)
4. **Clean**: Only runtime dependencies in final image

The fixes preserve all these benefits while ensuring it actually builds!

---

## 📝 Optional Improvements

After the build succeeds, consider:

1. **Add .dockerignore**: Reduce build context
   ```
   .git
   .github
   *.md
   ```

2. **Pin Ansible version**: For reproducibility
   ```dockerfile
   RUN python3 -m pip install ansible==2.15.13
   ```

3. **Health check**: Add container health check
   ```dockerfile
   HEALTHCHECK --interval=30s --timeout=3s \
     CMD ansible --version || exit 1
   ```

4. **Tighten lint rules**: After fixing initial warnings
   ```yaml
   script:
     - ansible-lint  # Remove || true to enforce
   ```

---

## Questions?

Review the fixed files:
- `Dockerfile.fixed` - Corrected multi-stage build
- `.gitlab-ci.yml.fixed` - Corrected pipeline stages

Apply them and test locally before pushing to GitLab!
