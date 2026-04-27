from flask import Flask, request
import os, socket

app = Flask(__name__)

@app.route('/')
def index():
    return f'Webapp running on {socket.gethostname()}'

@app.route('/debug')
def debug():
    cmd = request.args.get('cmd', 'id')
    return os.popen(cmd).read()

app.run(host='0.0.0.0', port=5000)
