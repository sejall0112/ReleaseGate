import os
from flask import Flask, jsonify

app = Flask(__name__)

ENVIRONMENT = os.environ.get("APP_ENV", "unknown")
VERSION = os.environ.get("APP_VERSION", "dev-local")


@app.route("/")
def index():
    return jsonify({
        "message": "ReleaseGate sample app",
        "environment": ENVIRONMENT,
        "version": VERSION,
    })


@app.route("/health")
def health():
    # This is the endpoint Jenkins hits after each promotion stage.
    # Swap in real checks here (DB connectivity, downstream deps, etc).
    return jsonify({"status": "healthy", "environment": ENVIRONMENT}), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
