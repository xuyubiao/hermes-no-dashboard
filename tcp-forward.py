#!/usr/bin/env python3
"""TCP forwarder: listen on 0.0.0.0:8080, forward to 127.0.0.1:18800.
Used in picoclaw+WebUI mode so the launcher WebUI is publicly accessible
via the service's routed port.
"""
import socket
import threading


def _fwd(src, dst):
    try:
        while True:
            d = src.recv(65536)
            if not d:
                break
            dst.sendall(d)
    except Exception:
        pass
    finally:
        for s in (src, dst):
            try:
                s.close()
            except Exception:
                pass


def _handle(client):
    try:
        upstream = socket.create_connection(("127.0.0.1", 18800), timeout=10)
    except Exception:
        client.close()
        return
    threading.Thread(target=_fwd, args=(client, upstream), daemon=True).start()
    _fwd(upstream, client)


def main():
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("0.0.0.0", 8080))
    srv.listen(100)
    while True:
        c, _ = srv.accept()
        threading.Thread(target=_handle, args=(c,), daemon=True).start()


if __name__ == "__main__":
    main()
