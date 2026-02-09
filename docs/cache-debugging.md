# Cache Invalidation Debugging

This guide explains how to debug Docker layer cache invalidation to understand **why** a build step wasn't cached.

## Quick Start

### 1. Build custom BuildKit

```bash
cd /path/to/buildkit
make images
```

### 2. Create a builder with custom image

```bash
docker buildx create \
  --driver=docker-container \
  --name=cache-debug \
  --driver-opt image=moby/buildkit:local \
  --bootstrap
```

### 3. Run your build

```bash
docker buildx build --builder=cache-debug --progress=plain -t myimage .
```

### 4. Check the logs

```bash
docker logs buildx_buildkit_cache-debug0 2>&1 | grep '\[cache'
```

## Log Format

### File Change Logs

When files in your build context change, you'll see:

```
[cache] 14:32:01.123 file added: /src/newfile.ts (layer: local source for context)
[cache] 14:32:01.456 file changed: /src/app.ts (layer: local source for context)
[cache] 14:32:01.789 file deleted: /src/oldfile.ts (layer: local source for context)
```

Each log includes:
- **Timestamp** - when the change was detected
- **Action** - `added`, `changed`, or `deleted`
- **Path** - the file path
- **Layer** - which build layer is affected

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
# Output: [cache] 14:32:05.123 file changed: /src/app.ts (layer: local source for context)
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
