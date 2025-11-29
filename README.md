
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



<img width="Building automation for dynamic blocks creation919" height="517" alt="image" src="https://github.com/user-attachments/assets/a976a932-0b68-4fb2-8f23-bde4b9fe19f9" />

<img width="918" height="420" alt="image" src="https://github.com/user-attachments/assets/f8e56025-b315-40bf-a08b- image6466b87eacd3" />

<img width="931" height="542" alt="image" src="https://github.com/user-attachments/assets/5beb442c-fae7-40f3-8d16-e6033895f9f6" />

<img width="949" height="543" alt="image" src="https://github.com/user-attachments/assets/b4b2a004-a8a5-4b96-85f6-2a18d1299ef1" />

<img width="952" height="180" alt="image" src="https://github.com/user-attachments/assets/2ddef800-cf3b-470e-8104-3bcd76c1e8c9" />



