#!/usr/bin/env python3
"""Sign local releases with one keychain identity and a stable app identifier."""
import hashlib
import os
from pathlib import Path
import secrets
import subprocess
import sys
import tempfile


def run(*args, **kwargs):
    return subprocess.run([str(arg) for arg in args], check=True, **kwargs)


app = Path(sys.argv[1])
override = os.environ.get("SPATIAL_STUDIO_SIGNING_IDENTITY")
if override:
    run("codesign", "--force", "--timestamp=none", "--sign", override, app)
    sys.exit(0)

os.umask(0o077)
default_store = Path.home() / "Library" / "Application Support" / "Spatial Studio" / "Local Signing"
store = Path(os.environ.get("SPATIAL_STUDIO_SIGNING_DIR", str(default_store)))
store.mkdir(mode=0o700, parents=True, exist_ok=True)
keychain = store / "signing.keychain-db"
password_file = store / "keychain-password"
certificate = store / "certificate.der"
name = "Spatial Studio Local Signing"

if not (keychain.exists() or password_file.exists() or certificate.exists()):
    password = secrets.token_hex(32)
    with tempfile.TemporaryDirectory(prefix="spatial-signing-") as folder:
        work = Path(folder)
        pem, private, p12 = (work / n for n in ("certificate.pem", "private.pem", "identity.p12"))
        run("openssl", "req", "-x509", "-newkey", "rsa:3072", "-nodes", "-sha256", "-days", "3650",
            "-subj", f"/CN={name}", "-addext", "basicConstraints=critical,CA:FALSE",
            "-addext", "keyUsage=critical,digitalSignature", "-addext", "extendedKeyUsage=codeSigning",
            "-keyout", private, "-out", pem, stderr=subprocess.DEVNULL)
        run("openssl", "pkcs12", "-export", "-inkey", private, "-in", pem, "-out", p12, "-name", name,
            "-passout", f"pass:{password}", "-keypbe", "PBE-SHA1-3DES", "-certpbe", "PBE-SHA1-3DES",
            "-macalg", "sha1")
        run("security", "create-keychain", "-p", password, keychain)
        try:
            run("security", "unlock-keychain", "-p", password, keychain)
            run("security", "import", p12, "-k", keychain, "-P", password, "-T", "/usr/bin/codesign")
            run("openssl", "x509", "-in", pem, "-outform", "DER", "-out", certificate)
            password_file.write_text(password)
        except BaseException:
            run("security", "delete-keychain", keychain)
            certificate.unlink(missing_ok=True)
            password_file.unlink(missing_ok=True)
            raise

if not (keychain.is_file() and password_file.is_file() and certificate.is_file()):
    sys.exit(f"Local signing identity is incomplete: {store}")

password = password_file.read_text().strip()
try:
    run("security", "unlock-keychain", "-p", password, keychain)
    fingerprint = hashlib.sha1(certificate.read_bytes()).hexdigest()
    run("codesign", "--force", "--timestamp=none", "--keychain", keychain, "--sign", fingerprint, app)
finally:
    run("security", "lock-keychain", keychain)
