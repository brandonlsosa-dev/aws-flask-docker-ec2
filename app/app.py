from flask import Flask, jsonify

app = Flask(__name__)

@app.route("/")
def home():
    return "Hello from Flask in Docker v2\n"

@app.route("/health")
def health():
    return jsonify(status="ok")
