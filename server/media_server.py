from flask import Flask, request, send_from_directory, jsonify
import os
import uuid
import time
from werkzeug.utils import secure_filename

app = Flask(__name__)

UPLOAD_FOLDER = os.path.abspath(os.environ.get('VEILCHAT_MEDIA_DIR', 'media_uploads'))
MAX_MB = 50
os.makedirs(UPLOAD_FOLDER, exist_ok=True)
app.config['MAX_CONTENT_LENGTH'] = MAX_MB * 1024 * 1024
MAX_FILE_SIZE = MAX_MB * 1024 * 1024

ALLOWED_EXTENSIONS = {'enc', 'png', 'jpg', 'jpeg', 'webp', 'aac', 'm4a', 'mp4', 'pdf', 'bin'}


def is_allowed_file(filename: str) -> bool:
    if '.' not in filename:
        return True  # default encrypted extension
    ext = filename.rsplit('.', 1)[1].lower()
    return ext in ALLOWED_EXTENSIONS


@app.after_request
def cors(r):
    r.headers['Access-Control-Allow-Origin'] = '*'
    r.headers['Access-Control-Allow-Methods'] = 'GET,POST,OPTIONS'
    r.headers['Access-Control-Allow-Headers'] = 'Content-Type,Authorization,X-Veil-Auth'
    return r


@app.errorhandler(413)
def too_large(_):
    return jsonify({'error': f'File too large (max {MAX_MB}MB)'}), 413


@app.route('/upload', methods=['POST'])
def upload():
    if 'file' not in request.files:
        return jsonify({'error': 'No file uploaded'}), 400

    f = request.files['file']
    if not f.filename:
        return jsonify({'error': 'No filename provided'}), 400

    raw_filename = secure_filename(f.filename) or 'file.enc'
    if not is_allowed_file(raw_filename):
        return jsonify({'error': 'File type not permitted'}), 400

    ext = raw_filename.rsplit('.', 1)[-1].lower() if '.' in raw_filename else 'enc'
    name = f"{int(time.time()*1000)}_{uuid.uuid4().hex[:8]}.{ext}"
    safe_path = os.path.join(UPLOAD_FOLDER, name)

    # Prevent path traversal
    if not os.path.commonpath([UPLOAD_FOLDER, safe_path]) == UPLOAD_FOLDER:
        return jsonify({'error': 'Invalid path'}), 400

    f.save(safe_path)
    size = os.path.getsize(safe_path)
    print(f'[MEDIA] +{name} ({size}B)')
    return jsonify({'filename': name, 'size': size}), 200


@app.route('/download/<filename>', methods=['GET'])
def download(filename):
    clean_name = os.path.basename(secure_filename(filename))
    if not clean_name:
        return jsonify({'error': 'Invalid filename'}), 400

    fp = os.path.join(UPLOAD_FOLDER, clean_name)
    if not os.path.commonpath([UPLOAD_FOLDER, fp]) == UPLOAD_FOLDER:
        return jsonify({'error': 'Access denied'}), 403

    if not os.path.exists(fp):
        return jsonify({'error': 'File not found'}), 404

    print(f'[MEDIA] -{clean_name}')
    return send_from_directory(UPLOAD_FOLDER, clean_name)


@app.route('/health', methods=['GET'])
def health():
    file_count = len(os.listdir(UPLOAD_FOLDER)) if os.path.exists(UPLOAD_FOLDER) else 0
    return jsonify({'status': 'ok', 'files': file_count}), 200


if __name__ == '__main__':
    host = os.environ.get('VEILCHAT_MEDIA_HOST', '0.0.0.0')  # nosec B104
    port = int(os.environ.get('VEILCHAT_MEDIA_PORT', 5001))
    print(f'[MEDIA] Listening on {host}:{port}')
    app.run(host=host, port=port, debug=False, threaded=True)
