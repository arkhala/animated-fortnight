# Torware Minimal

Ultra-lightweight Tor relay and Snowflake proxy for Flux Cloud deployment.

## Features

- 🧅 **Tor Bridge** (obfs4) - Help censored users connect
- 🔁 **Middle Relay** - Route Tor traffic
- 🚪 **Exit Relay** - Final hop (reduced policy)
- ❄️ **Snowflake Proxy** - WebRTC transport for censored users
- 📊 **Stats Logging** - Periodic stats to stdout/docker logs

## Resource Usage

| Mode | CPU | RAM | Disk |
|------|-----|-----|------|
| Bridge | 0.5 | 80-100 MB | <500 MB |
| Middle | 0.5 | 80-100 MB | <500 MB |
| Snowflake | 0.2 | 30-50 MB | <100 MB |
| Bridge+Snowflake | 0.6 | 100-128 MB | <500 MB |

**Image size: ~30 MB**

## Quick Start

```bash
# Bridge relay
docker run -d --name tor-bridge \
  -e MODE=bridge \
  -e NICKNAME=MyBridge \
  -e BANDWIDTH=5 \
  -p 9001:9001 -p 9002:9002 \
  ghcr.io/arkhala/torware:minimal

# Snowflake proxy
docker run -d --name snowflake \
  -e MODE=snowflake \
  -e SNOWFLAKE_CAPACITY=10 \
  ghcr.io/arkhala/torware:minimal

# Bridge + Snowflake
docker run -d --name tor-full \
  -e MODE=bridge+snowflake \
  -e NICKNAME=MyNode \
  -p 9001:9001 -p 9002:9002 \
  ghcr.io/arkhala/torware:minimal
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `MODE` | `bridge` | `bridge`, `middle`, `exit`, `snowflake`, `bridge+snowflake` |
| `NICKNAME` | `FluxTorRelay` | Relay nickname (1-19 alphanumeric) |
| `CONTACT` | `` | Contact email (optional) |
| `BANDWIDTH` | `5` | Bandwidth limit in Mbit/s |
| `ORPORT` | `9001` | Tor OR port |
| `OBFS4PORT` | `9002` | obfs4 pluggable transport port |
| `SNOWFLAKE_CAPACITY` | `10` | Max concurrent Snowflake clients |
| `STATS_INTERVAL` | `300` | Stats logging interval (seconds) |

## View Stats

Stats are logged to stdout every `STATS_INTERVAL` seconds:

```bash
docker logs -f tor-bridge
```

Example output:
```
[STATS 2026-02-02 12:00:00] ════════════════════════════════════════
[STATS 2026-02-02 12:00:00] === TOR RELAY STATS ===
[STATS 2026-02-02 12:00:00] Mode: bridge
[STATS 2026-02-02 12:00:00] Nickname: MyBridge
[STATS 2026-02-02 12:00:00] Fingerprint: ABCD1234...
[STATS 2026-02-02 12:00:00] Traffic: ↓ 1.23 GB | ↑ 2.45 GB
[STATS 2026-02-02 12:00:00] === SNOWFLAKE PROXY STATS ===
[STATS 2026-02-02 12:00:00] Total connections: 42
[STATS 2026-02-02 12:00:00] Traffic: ↓ 512 MB | ↑ 489 MB
[STATS 2026-02-02 12:00:00] ════════════════════════════════════════
```

## Flux Cloud Deployment

1. Push image to GHCR (automated via GitHub Actions)
2. Go to [FluxCloud](https://cloud.runonflux.com)
3. Deploy with Docker using `ghcr.io/arkhala/torware:minimal`
4. Configure environment variables
5. Set resources: 0.5 CPU, 100 MB RAM, 1 GB disk

## License

MIT
