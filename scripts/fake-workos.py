"""A fake WorkOS AuthKit for bin/test-cli: python3 scripts/fake-workos.py PORT
CLIENT_ID CLIENT_SECRET EMAIL.

Serves the two endpoints Tun's (:workos ...) strategy uses (spec/auth.md
3.5.1) at http://127.0.0.1:PORT, the AuthKit domain the server is given.
/oauth2/authorize signs in EMAIL at once and sends the browser back with a
code; /oauth2/token checks the client's credentials, the redirect URI and
the PKCE verifier as AuthKit would, and answers with an ID token for EMAIL.
Tun does not check the token's signature, so it is junk.
"""

import base64
import hashlib
import json
import secrets
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlencode, urlparse

port, client_id, client_secret, email = int(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
issuer = f"http://127.0.0.1:{port}"
codes = {}  # code -> the authorization request's parameters


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def id_token(nonce):
    now = int(time.time())
    claims = {"iss": issuer, "aud": client_id, "sub": "user_01TESTCLI", "email": email,
              "email_verified": True, "nonce": nonce, "iat": now, "exp": now + 300}
    header = b64url(json.dumps({"alg": "RS256", "typ": "JWT"}).encode())
    return f"{header}.{b64url(json.dumps(claims).encode())}.c2lnbmF0dXJl"


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def answer(self, status, body=b"", headers=()):
        self.send_response(status)
        for name, value in headers:
            self.send_header(name, value)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        url = urlparse(self.path)
        if url.path != "/oauth2/authorize":
            return self.answer(404)
        request = {key: values[0] for key, values in parse_qs(url.query).items()}
        if request.get("client_id") != client_id:
            return self.answer(400, b"unknown client")
        code = secrets.token_hex(16)
        codes[code] = request
        back = request["redirect_uri"] + "?" + urlencode({"code": code, "state": request["state"]})
        self.answer(302, headers=[("Location", back)])

    def do_POST(self):
        if urlparse(self.path).path != "/oauth2/token":
            return self.answer(404)
        length = int(self.headers.get("Content-Length", "0"))
        form = {key: values[0] for key, values in parse_qs(self.rfile.read(length).decode()).items()}
        request = codes.pop(form.get("code", ""), None)
        verifier = form.get("code_verifier", "").encode()
        if (request is None
                or form.get("client_id") != client_id
                or form.get("client_secret") != client_secret
                or form.get("redirect_uri") != request["redirect_uri"]
                or b64url(hashlib.sha256(verifier).digest()) != request.get("code_challenge")):
            body = json.dumps({"error": "invalid_grant"}).encode()
            return self.answer(400, body, [("Content-Type", "application/json")])
        body = json.dumps({"access_token": "at", "token_type": "Bearer",
                           "id_token": id_token(request["nonce"])}).encode()
        self.answer(200, body, [("Content-Type", "application/json")])


ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
