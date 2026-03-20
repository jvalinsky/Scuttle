import socket
import sys

def main():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.bind(('127.0.0.1', 8009))
    s.listen(1)
    print("Listening on 8009...", flush=True)
    conn, addr = s.accept()
    print(f"Accepted connection from {addr}", flush=True)
    data = conn.recv(1024)
    print(f"Received {len(data)} bytes: {data.hex()}", flush=True)

if __name__ == '__main__':
    main()
