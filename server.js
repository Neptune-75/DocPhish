const express = require('express');
const multer = require('multer');
const fs = require('fs');
const path = require('path');
const UAParser = require('ua-parser-js');
const fetch = require('node-fetch');
const readline = require('readline');
const crypto = require('crypto');

// Prompt for admin key at startup
function getAdminKey(callback) {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
    rl.question('Enter admin key for this session (leave blank for random): ', (input) => {
        rl.close();
        callback(input || crypto.randomBytes(16).toString('hex'));
    });
}

getAdminKey((ADMIN_KEY) => {
    const app = express();
    const PORT = process.env.PORT || 3000;

    console.log(`Your admin key is: ${ADMIN_KEY}`);
    console.log(`Access gallery at: http://localhost:${PORT}/gallery?key=${ADMIN_KEY}`);

    app.use(express.static('public'));
    const UPLOADS_DIR = path.join(__dirname, 'uploads');
    if (!fs.existsSync(UPLOADS_DIR)) fs.mkdirSync(UPLOADS_DIR);
    const META_PATH = path.join(UPLOADS_DIR, 'metadata.json');
    function loadMeta() {
        if (!fs.existsSync(META_PATH)) return [];
        try { return JSON.parse(fs.readFileSync(META_PATH, 'utf8')); } catch { return []; }
    }
    function saveMeta(meta) {
        fs.writeFileSync(META_PATH, JSON.stringify(meta, null, 2));
    }
    const storage = multer.diskStorage({
        destination: (req, file, cb) => cb(null, UPLOADS_DIR),
                                       filename: (req, file, cb) => cb(null, Date.now() + '.png'),
    });
    const upload = multer({ storage });
    function getClientIp(req) {
        return req.headers['x-forwarded-for']?.split(',')[0] || req.socket.remoteAddress;
    }
    app.post('/upload', upload.single('photo'), async (req, res) => {
        if (!req.file) return res.status(400).json({ status: 'error', message: 'No file received' });
        const parser = new UAParser(req.headers['user-agent']);
        const deviceInfo = parser.getResult();
        const ip = getClientIp(req);
        let location = {};
        try {
            const geoRes = await fetch(`https://ipinfo.io/${ip}/json`);
            location = await geoRes.json();
        } catch { location = {}; }
        const meta = loadMeta();
        meta.push({
            filename: req.file.filename,
            ip,
            location: { city: location.city, country: location.country },
            device: {
                type: deviceInfo.device.type,
                model: deviceInfo.device.model,
                os: deviceInfo.os,
                browser: deviceInfo.browser
            },
            timestamp: Date.now()
        });
        saveMeta(meta);
        res.json({ status: 'ok', filename: req.file.filename });
    });
    app.use('/uploads', express.static(UPLOADS_DIR));
    app.get('/api/uploads', (req, res) => { res.json(loadMeta()); });
    app.get('/gallery', (req, res) => {
        const key = req.query.key;
        if (key !== ADMIN_KEY) return res.status(403).send('Access denied: Invalid admin key');
        res.sendFile(path.join(__dirname, 'public', 'gallery.html'));
    });
    const DELETE_AFTER_MINUTES = 30;
    function deleteOldFiles() {
        const meta = loadMeta();
        const now = Date.now();
        let changed = false;
        const filteredMeta = meta.filter(entry => {
            const filePath = path.join(UPLOADS_DIR, entry.filename);
            const ageMinutes = (now - entry.timestamp) / (1000 * 60);
            if (ageMinutes > DELETE_AFTER_MINUTES) {
                if (fs.existsSync(filePath)) fs.unlinkSync(filePath);
                changed = true;
                return false;
            }
            return true;
        });
        if (changed) saveMeta(filteredMeta);
    }
    setInterval(deleteOldFiles, 5 * 60 * 1000);
    app.listen(PORT, () => {
        console.log(`Server running at http://localhost:${PORT}`);
    });
});
