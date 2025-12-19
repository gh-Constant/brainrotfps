# Brainrot FPS

A Roblox FPS game built with Rojo and Wally.

## Setup

### Prerequisites

1. Install [Aftman](https://github.com/LPGhatguy/aftman) (tool manager)
2. Install [Rojo VS Code Extension](https://marketplace.visualstudio.com/items?itemName=evaera.vscode-rojo)

### Installation

```bash
# Install tools (Rojo, Wally)
aftman install

# Install packages
wally install
```

### Development

```bash
# Start Rojo server
rojo serve

# Build to file
rojo build -o game.rbxl
```

## Project Structure

```
src/
├── Client/          # Client-side scripts (StarterPlayerScripts)
├── Server/          # Server-side scripts (ServerScriptService)
└── Shared/          # Shared modules (ReplicatedStorage)

Packages/            # Wally packages (auto-generated)
```

## Configuration

The project uses `$ignoreUnknownInstances: true` on all containers, which means:

- Existing instances in Roblox Studio are preserved
- Only files in `src/` are synced
- Safe to use with existing place files
