from flask import Flask, request, send_from_directory, jsonify
import os, uuid, time

app = Flask(__name__)

UPLOAD_FOLDER = 'media_uploads'
MAX_MB = 50
os.makedirs(UPLOAD_FOLDER, exist_ok=True)
app.config['MAX_CONTENT_LENGTH'] = MAX_MB * 1024 * 1024
MAX_FILE_SIZE = MAX_MB * 1024 * 1024

@app.after_request
def cors(r):
    r.headers['Access-Control-Allow-Origin']  = '*'
    r.headers['Access-Control-Allow-Methods'] = 'GET,POST,OPTIONS'
    r.headers['Access-Control-Allow-Headers'] = 'Content-Type'
    return r

@app.errorhandler(413)
def too_large(_): return jsonify({'error':f'File too large (max {MAX_MB}MB)'}), 413

@app.route('/upload', methods=['POST'])
def upload():
    if 'file' not in request.files: return jsonify({'error':'No file'}), 400
    f = request.files['file']
    if not f.filename: return jsonify({'error':'No filename'}), 400
    ext = f.filename.rsplit('.',1)[-1].lower() if '.' in f.filename else 'enc'
    name = f'{int(time.time()*1000)}_{uuid.uuid4().hex[:8]}.{ext}'
    path = os.path.join(UPLOAD_FOLDER, name)
    f.save(path)
    size = os.path.getsize(path)
    print(f'[MEDIA] +{name} ({size}B)')
    return jsonify({'filename': name, 'size': size}), 200

@app.route('/download/<filename>')
def download(filename):
    filename = os.path.basename(filename)
    fp = os.path.join(UPLOAD_FOLDER, filename)
    if not os.path.exists(fp): return jsonify({'error':'Not found'}), 404
    print(f'[MEDIA] -{filename}')
    return send_from_directory(UPLOAD_FOLDER, filename)

@app.route('/health')
def health():
    return jsonify({'status':'ok','files':len(os.listdir(UPLOAD_FOLDER))}), 200

if __name__ == '__main__':
    print('[MEDIA] Listening on 0.0.0.0:5001')
    app.run(host='0.0.0.0', port=5001, debug=False, threaded=True)
