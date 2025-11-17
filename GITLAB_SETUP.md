# CyMyToolbox - Internal GitLab Setup Guide

## Overview
This guide walks you through setting up the cymytoolbox project in your internal GitLab instance at `tenant-git.orl01.cymycloud.com` and configuring automated builds to your internal registry.

## Prerequisites
- GitLab project created at `https://tenant-git.orl01.cymycloud.com/cymycloud/cymytoolbox`
- Access to `registry.orl01.cymycloud.com`
- GitLab Runner configured in Kubernetes cluster (already done)

## Step 1: Create GitLab Project

1. Navigate to `https://tenant-git.orl01.cymycloud.com/cymycloud`
2. Create a new project named `cymytoolbox`
3. Set visibility to Private or Internal (as per your security requirements)

## Step 2: Add GitLab as Remote

```bash
cd /home/richardevans/Documents/Code/cymycloud/cymytoolbox

# Add internal GitLab as remote
git remote add gitlab git@tenant-git.orl01.cymycloud.com:cymycloud/cymytoolbox.git

# Or if using HTTPS:
# git remote add gitlab https://tenant-git.orl01.cymycloud.com/cymycloud/cymytoolbox.git

# Push to GitLab
git push gitlab main
```

## Step 3: Configure Registry Authentication (if needed)

The CI/CD pipeline uses GitLab's built-in registry authentication via `CI_REGISTRY_USER` and `CI_REGISTRY_PASSWORD` variables, which are automatically provided to CI jobs.

If you need to manually configure registry access:

```bash
# In GitLab UI: Settings > CI/CD > Variables
# Add these variables if not automatically available:
CI_REGISTRY_USER: <your-registry-username>
CI_REGISTRY_PASSWORD: <your-registry-token>
```

## Step 4: How the CI/CD Pipeline Works

The `.gitlab-ci.yml` file uses **Kaniko** for secure, rootless container builds:

- **No privileged mode required** - More secure, meets FedRAMP/NIST requirements
- **Automatic tagging**:
  - `latest` - Built from main/master branch
  - `<commit-sha>` - Every build gets a unique tag
  - `<git-tag>` - If you create a git tag (e.g., `v1.0.0`)

### Build Triggers:
- Push to main branch → builds `latest` tag
- Create git tag → builds versioned release
- Merge request → builds with branch name + SHA

## Step 5: Create a Version Tag (Optional)

For semantic versioning:

```bash
# Tag a release
git tag -a v1.0.0 -m "Initial internal release"
git push gitlab v1.0.0

# This will build: registry.orl01.cymycloud.com/cymycloud/cymytoolbox:v1.0.0
```

## Step 6: Update Projects to Use Internal Image

After the first successful build, update your other projects (like cymy-checks-every-5min) to use the internal image:

**Old `.gitlab-ci.yml`:**
```yaml
image: docker.io/richevanscymy/cymytoolbox:latest
```

**New `.gitlab-ci.yml`:**
```yaml
image: registry.orl01.cymycloud.com/cymycloud/cymytoolbox:latest
```

## Image Paths

After building, your images will be available at:

- **Latest**: `registry.orl01.cymycloud.com/cymycloud/cymytoolbox:latest`
- **By commit**: `registry.orl01.cymycloud.com/cymycloud/cymytoolbox:<commit-sha>`
- **By version**: `registry.orl01.cymycloud.com/cymycloud/cymytoolbox:v1.0.0`

## Verification

After pushing to GitLab:

1. Check CI/CD pipeline: `https://tenant-git.orl01.cymycloud.com/cymycloud/cymytoolbox/-/pipelines`
2. Monitor the build job logs
3. Verify image in registry: `https://registry.orl01.cymycloud.com/` (or via GitLab Container Registry UI)

## Troubleshooting

### Build fails with "unauthorized" error:
- Verify registry credentials in GitLab Settings > CI/CD > Variables
- Ensure the GitLab project has access to the registry

### Kaniko image pull fails:
- Add `gcr.io` (Google Container Registry) to allowed registries
- Or mirror the Kaniko image to your internal registry

### Runner not picking up jobs:
- Check runner tags match (jobs use `tenant-platform-runner` tag)
- Verify runner is active: `kubectl get pods -n gitlab-runner`

## Security Notes

- Kaniko builds don't require privileged containers (better security)
- Uses GitLab's native authentication (no credentials in files)
- All traffic stays internal (GitLab → K8s → Registry)
- Meets FedRAMP/NIST 800-53 requirements for container builds
