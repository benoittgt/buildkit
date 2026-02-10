# Cache Invalidation Debugging

This guide explains how to debug Docker layer cache invalidation to understand **why** a build step wasn't cached.

## Quick Start

### Option A: Use published image (easiest)

```bash
# Create a builder with cache debugging
docker buildx create \
  --driver=docker-container \
  --name=cache-debug \
  --driver-opt image=benoittigeotlifen/buildkit-cache-debug:latest \
  --bootstrap

# Use it for builds
docker buildx use cache-debug
docker buildx build -t myimage .

# Check cache logs
docker logs buildx_buildkit_cache-debug0 2>&1 | grep '\[cache'
```

### Option B: Use helper script

```bash
# Source the helper script (auto-creates builder)
source /path/to/buildkit/scripts/use-local-buildkit.sh

# Build your images
docker buildx build -t myimage .

# Check cache logs
cache-logs
```

### Option C: Build from source

```bash
# Clone and build
cd /path/to/buildkit
make images

# Use local image
docker buildx create \
  --driver=docker-container \
  --name=cache-debug \
  --driver-opt image=moby/buildkit:local \
  --bootstrap
```

## How It Works

```
┌─────────────────┐     make images      ┌──────────────────────┐
│  BuildKit Code  │ ──────────────────▶  │ moby/buildkit:local  │
│  (Go source)    │                      │ (Docker image)       │
└─────────────────┘                      └──────────────────────┘
                                                   │
                                                   ▼
┌─────────────────┐   --driver-opt       ┌──────────────────────┐
│  docker buildx  │ ◀───────────────────│ buildx builder       │
│  build ...      │   image=...local     │ (container running   │
└─────────────────┘                      │  your custom image)  │
                                         └──────────────────────┘
```

- `make images` compiles Go code and builds a Docker image
- `--driver-opt image=moby/buildkit:local` tells buildx to use YOUR image
- The builder is a container running `buildkitd` with your changes
- Logs go to the container's stderr (use `docker logs` to see them)

## Distributing Your Custom BuildKit

You can push your custom BuildKit to Docker Hub or any registry:

```bash
# Tag with your username
docker tag moby/buildkit:local benoittigeotlifen/buildkit-cache-debug:latest

# Push to Docker Hub
docker push benoittigeotlifen/buildkit-cache-debug:latest
```

Others can then use it:

```bash
docker buildx create \
  --driver=docker-container \
  --name=cache-debug \
  --driver-opt image=benoittigeotlifen/buildkit-cache-debug:latest \
  --bootstrap
```

## Log Format

### File Change Logs

When files in your build context change, you'll see structured logs with all changes grouped:

```
level=info msg="[cache] file changes detected" changes="[added: /src/newfile.ts changed: /src/app.ts]" layer="local source for context"
```

Each log includes:
- **changes** - list of all file changes (`added`, `changed`, `deleted`)
- **layer** - which build layer is affected (e.g., "local source for context")

### Cache Miss Logs

When a build step cache is invalidated:

```
level=info msg="[cache:miss] no cache hit, executing operation" reason=no_cache_match vertex_name="[2/3] COPY src /app"
level=info msg="[cache:miss] no matching cache keys (inputs changed or first build)" vertex_name="[3/3] RUN npm build"
```

**Reasons:**
- `no_cache_match` - inputs changed or no previous cache
- `cache_disabled` - `--no-cache` flag or `DOCKER_BUILDKIT=0`

## Example Workflow

```bash
# First build (populates cache)
docker buildx build --builder=cache-debug -t myapp .

# Modify a file
echo "// comment" >> src/app.ts

# Second build (see what invalidated)
docker buildx build --builder=cache-debug -t myapp .

# Check which file triggered invalidation
docker logs buildx_buildkit_cache-debug0 2>&1 | grep '\[cache\]'
# Output: level=info msg="[cache] file changes detected" changes="[changed: /src/app.ts]" layer="local source for context"
```

## Tips

### Filter by step name

```bash
docker logs buildx_buildkit_cache-debug0 2>&1 | grep -E '\[cache|COPY|RUN'
```

### Watch logs in real-time

```bash
docker logs -f buildx_buildkit_cache-debug0 2>&1 | grep '\[cache'
```

### Clear cache and start fresh

```bash
docker buildx prune --builder=cache-debug
```

### Reset the builder

```bash
docker buildx rm cache-debug
docker buildx create --driver=docker-container --name=cache-debug \
  --driver-opt image=moby/buildkit:local --bootstrap
```

## Common Cache Invalidation Causes

| Symptom | Likely Cause |
|---------|--------------|
| `file changed: /package-lock.json` | Dependencies updated |
| `file changed: /.git/...` | Git metadata in context (add to `.dockerignore`) |
| `file added: /node_modules/...` | node_modules in context (add to `.dockerignore`) |
| `file changed: /src/...` | Source code modified |
| Many `file added` on first build | Normal - cache is being populated |

## Optimizing Your Dockerfile

Once you identify which files trigger cache invalidation, consider:

1. **Order matters**: Put frequently-changing files later in Dockerfile
2. **Use `.dockerignore`**: Exclude files that shouldn't affect builds
3. **Multi-stage builds**: Separate build dependencies from runtime
4. **Copy selectively**: `COPY package*.json ./` before `COPY . .`
