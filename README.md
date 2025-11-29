
# Blockchain with Python

A sample implementation using Python 3.12.

## Features

- ✅ Genesis Block with initial data
- ✅ Block chaining with previous_hash
- ✅ Proof-of-Work (mineração)
- ✅ Chain integrity validation
- ✅ Robust and extensible structure
- ✅ Containerized with Docker

## Blocks structure

Each block contains:
- `index`: Sequential block number
- `timestamp`: Creation date/time
- `data`: Transaction information
- `previous_hash`: Hash of the previous block
- `hash`: Hash of the current block
- `nonce`: Counter for proof-of-work


### How run with Docker 

```bash
# I
docker build -t python-blockchain .
Image building
# Run container
docker run -it --rm python-blockchain

# Run with volume to saver data:
docker run -it --rm -v $(pwd)/data:/app/data python-blockchain


## Usage:

### 1. Build Docker image:
```bash
docker build -t python-blockchain .
----------------------------------------------------------




