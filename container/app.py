# P6 M2: tiny HTTP app (Python standard library only) that proves, from outside, which code,
# which Container Apps revision and which replica answered a request.
#   app_version : from APP_VERSION (baked into the image; can be overridden per revision)
#   revision    : CONTAINER_APP_REVISION, set by Azure Container Apps ("n/a" elsewhere, e.g. ACI)
#   replica     : CONTAINER_APP_REPLICA_NAME, or the hostname when not running in Container Apps
# /health returns "ok". /slow?s=N waits N seconds (max 10) before answering, so requests overlap
# and the HTTP concurrency scale rule can be tested.
import os
import socket
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("PORT", "8080"))


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith("/health"):
            body = "ok\n"
        elif self.path.startswith("/slow"):
            try:
                seconds = min(10.0, max(0.0, float(self.path.split("s=", 1)[1].split("&")[0])))
            except (IndexError, ValueError):
                seconds = 3.0
            time.sleep(seconds)
            body = f"slept={seconds}\nreplica={os.environ.get('CONTAINER_APP_REPLICA_NAME', socket.gethostname())}\n"
        else:
            body = (
                f"app_version={os.environ.get('APP_VERSION', 'unset')}\n"
                f"revision={os.environ.get('CONTAINER_APP_REVISION', 'n/a')}\n"
                f"replica={os.environ.get('CONTAINER_APP_REPLICA_NAME', socket.gethostname())}\n"
            )
        data = body.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, fmt, *args):
        # One line per request to stdout (visible in container logs).
        print(f"{self.address_string()} {fmt % args}", flush=True)


if __name__ == "__main__":
    print(f"listening on :{PORT}", flush=True)
    ThreadingHTTPServer(("", PORT), Handler).serve_forever()
