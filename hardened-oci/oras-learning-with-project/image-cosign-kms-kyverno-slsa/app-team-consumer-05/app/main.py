"""Minimal FastAPI app. Deliberately trivial - the lesson is the Dockerfile,
the manifest, and the verification around it, not the application code.

/healthz is what the Kubernetes probes and the Docker HEALTHCHECK call.
/whoami exposes the effective UID so you can prove non-root at runtime rather
than trusting the image metadata (CIS Docker 4.1).
"""
import os

from fastapi import FastAPI

app = FastAPI(title="example-api", docs_url=None, redoc_url=None)


@app.get("/healthz")
def healthz() -> dict:
    return {"status": "ok"}


@app.get("/whoami")
def whoami() -> dict:
    # If uid is 0 here, the securityContext is not doing its job.
    return {
        "uid": os.getuid(),
        "gid": os.getgid(),
        "root_fs_writable": os.access("/", os.W_OK),
    }
