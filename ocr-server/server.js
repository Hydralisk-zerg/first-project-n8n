const express = require('express');
const multer = require('multer');
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const JSZip = require('jszip');
const { XMLParser } = require('fast-xml-parser');

const app = express();
const port = 3001;

// Простая in-memory очередь задач OCR (для async режима)
const jobs = {}; // jobId -> { status: 'processing'|'done'|'error', createdAt, updatedAt, result?, error? }

function createJob() {
    const id = `job_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
    const now = Date.now();
    jobs[id] = { status: 'processing', createdAt: now, updatedAt: now };
    return id;
}

function setJobResult(id, result) {
    if (jobs[id]) {
        jobs[id].status = 'done';
        jobs[id].result = result;
        jobs[id].updatedAt = Date.now();
    }
}

function setJobError(id, error) {
    if (jobs[id]) {
        jobs[id].status = 'error';
        jobs[id].error = typeof error === 'string' ? error : (error?.message || String(error));
        jobs[id].updatedAt = Date.now();
    }
}

// Периодическая очистка старых задач (старше 1 часа)
setInterval(() => {
    const cutoff = Date.now() - 60 * 60 * 1000;
    for (const [id, job] of Object.entries(jobs)) {
        if ((job.updatedAt || job.createdAt || 0) < cutoff) {
            delete jobs[id];
        }
    }
}, 15 * 60 * 1000);

// Middleware для установки timeout
app.use((req, res, next) => {
    res.setTimeout(300000, () => { // 5 минут
        console.log('Request timeout!');
        res.status(408).json({ error: 'Request timeout' });
    });
    next();
});

// Настройка multer для загрузки файлов в память
const upload = multer({ 
    storage: multer.memoryStorage(),
    limits: { fileSize: 20 * 1024 * 1024 } // 20MB
});

app.use(express.json());

// Создаем директории если их нет
['/files/uploads', '/files/ocr-output'].forEach(dir => {
    if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir, { recursive: true });
    }
});

// ===== DOCX text extraction helper =====
async function extractDocxTextFromBuffer(buffer) {
    const zip = await JSZip.loadAsync(buffer);
    const docFile = zip.file('word/document.xml');
    if (!docFile) throw new Error('DOCX document.xml not found');
    const xml = await docFile.async('string');
    const parser = new XMLParser({ ignoreAttributes: false, trimValues: true });
    const json = parser.parse(xml);
    const out = [];
    (function collect(node) {
        if (node == null) return;
        if (typeof node === 'string') { out.push(node); return; }
        if (Array.isArray(node)) { node.forEach(collect); return; }
        for (const [k, v] of Object.entries(node)) {
            if (k === 'w:t') {
                if (typeof v === 'string') out.push(v);
                else collect(v);
            } else {
                collect(v);
            }
        }
    })(json);
    const text = out.join(' ').replace(/[ \t]+/g, ' ').replace(/\s+\n/g, '\n').trim();
    return text;
}

// Endpoint для multipart form data (поддержка PDF / DOC / DOCX / изображений; sync и async)
// Принимаем любой ключ поля (file/data/...), берём первый файл
app.post('/ocr', upload.any(), (req, res) => {
    const timestamp = Date.now();
    let tempFilePath = null;
    let isAsync = false;

    try {
        let file = null;
        if (Array.isArray(req.files) && req.files.length > 0) file = req.files[0];
        if (!file && req.file) file = req.file;
        if (!file) return res.status(400).json({ success: false, error: 'No file uploaded' });

        // Детектируем тип по сигнатуре
        const buf = file.buffer;
        if (!Buffer.isBuffer(buf) || buf.length === 0) {
            return res.status(400).json({ success: false, error: 'Empty file buffer' });
        }
        const b0 = buf[0];
        const b1 = buf[1];
        const b2 = buf[2];
        const b3 = buf[3];
        const header5 = buf.slice(0, 5).toString('ascii');
        const isPdf = header5 === '%PDF-';
        const isDocOle = (b0 === 0xD0 && b1 === 0xCF && b2 === 0x11 && b3 === 0xE0);
        const isZipPk = (b0 === 0x50 && b1 === 0x4B);
        let imageExt = 'png';
        if (b0 === 0x89 && b1 === 0x50 && b2 === 0x4E && b3 === 0x47) imageExt = 'png';
        else if (b0 === 0xFF && b1 === 0xD8 && b2 === 0xFF) imageExt = 'jpg';
        else if (header5.slice(0, 4) === 'RIFF') imageExt = 'webp';

        const fileKind = isPdf ? 'pdf' : (isDocOle ? 'doc' : (isZipPk ? 'docx' : 'image'));

        // Сохраняем файл с подходящим расширением
        const tempFileName = fileKind === 'pdf' ? `temp_${timestamp}.pdf`
                         : fileKind === 'doc' ? `temp_${timestamp}.doc`
                         : fileKind === 'docx' ? `temp_${timestamp}.docx`
                         : `temp_${timestamp}.${imageExt}`;
        tempFilePath = `/files/uploads/${tempFileName}`;
    fs.writeFileSync(tempFilePath, buf);
        console.log(`Multipart file saved: ${tempFilePath} (kind=${fileKind}, size=${buf.length})`);

        // async режим
        isAsync = req.query.async === '1' || req.headers['x-async'] === '1' || req.headers['x-async'] === 'true';
        if (isAsync) {
            const jobId = createJob();
            console.log(`Async mode enabled on /ocr, jobId=${jobId}`);
            res.status(202).json({ success: true, accepted: true, jobId });

            setImmediate(() => {
                try {
                    let result;
                    if (fileKind === 'pdf') {
                        result = runOcrForPdfFile(tempFilePath, timestamp, tempFileName, buf.length);
                    } else if (fileKind === 'doc' || fileKind === 'docx') {
                        const pdfPath = convertDocToPdf(tempFilePath, timestamp);
                        result = runOcrForPdfFile(pdfPath, timestamp, path.basename(pdfPath), buf.length);
                    } else {
                        result = runOcrForImageFile(tempFilePath, timestamp, tempFileName, buf.length);
                    }
                    setJobResult(jobId, result);
                } catch (e) {
                    console.error('Async OCR error (/ocr):', e.message);
                    setJobError(jobId, e.message);
                } finally {
                    cleanupTempArtifacts(timestamp, tempFilePath);
                }
            });
            return;
        }

        // sync режим
        let result;
        if (fileKind === 'pdf') {
            result = runOcrForPdfFile(tempFilePath, timestamp, tempFileName, buf.length);
        } else if (fileKind === 'doc' || fileKind === 'docx') {
            const pdfPath = convertDocToPdf(tempFilePath, timestamp);
            result = runOcrForPdfFile(pdfPath, timestamp, path.basename(pdfPath), buf.length);
        } else {
            result = runOcrForImageFile(tempFilePath, timestamp, tempFileName, buf.length);
        }
        res.json(result);

    } catch (error) {
        console.error('OCR Error (/ocr):', error.message);
        let originalName = 'unknown';
        try {
            const f = (Array.isArray(req.files) && req.files[0]) || req.file;
            if (f && f.originalname) originalName = f.originalname;
        } catch {}
        res.json({ success: false, error: error.message, text: '', fileName: originalName });
    } finally {
        if (!isAsync) {
            cleanupTempArtifacts(timestamp, tempFilePath);
        }
    }
});

// Extract text from DOCX (multipart) — fast path for digitally-generated docs
app.post('/extract-docx', upload.any(), async (req, res) => {
    try {
        let file = null;
        if (Array.isArray(req.files) && req.files.length > 0) file = req.files[0];
        if (!file && req.file) file = req.file;
        if (!file) return res.status(400).json({ success: false, error: 'No file uploaded' });
        const buf = file.buffer;
        if (!Buffer.isBuffer(buf) || buf.length === 0) {
            return res.status(400).json({ success: false, error: 'Empty file buffer' });
        }
        const isZipPk = buf[0] === 0x50 && buf[1] === 0x4B;
        if (!isZipPk) return res.status(400).json({ success: false, error: 'Not a DOCX (PK signature missing)' });

        const text = await extractDocxTextFromBuffer(buf);
        return res.json({ success: true, mode: 'docx-extract', text, pages: [{ pageNumber: 1, text }] });
    } catch (e) {
        console.error('DOCX extract error:', e.message);
        return res.status(500).json({ success: false, error: e.message });
    }
});

// Extract text from DOCX (binary body)
app.post('/extract-docx-binary', express.raw({ limit: '50mb', type: '*/*' }), async (req, res) => {
    try {
        const buf = req.body;
        if (!buf || !buf.length) return res.status(400).json({ success: false, error: 'No binary data received' });
        const isZipPk = buf[0] === 0x50 && buf[1] === 0x4B;
        if (!isZipPk) return res.status(400).json({ success: false, error: 'Not a DOCX (PK signature missing)' });
        const text = await extractDocxTextFromBuffer(buf);
        return res.json({ success: true, mode: 'docx-extract', text, pages: [{ pageNumber: 1, text }] });
    } catch (e) {
        console.error('DOCX extract error (binary):', e.message);
        return res.status(500).json({ success: false, error: e.message });
    }
});

app.get('/health', (req, res) => {
    res.json({ status: 'OK', service: 'OCR API', time: new Date().toISOString() });
});

// Получение статуса/результата задачи
app.get('/result/:jobId', (req, res) => {
    const { jobId } = req.params;
    const job = jobs[jobId];
    if (!job) {
        return res.status(404).json({ success: false, error: 'Job not found' });
    }
    if (job.status === 'processing') {
        return res.status(202).json({ success: true, jobId, status: job.status });
    }
    res.json({ success: true, jobId, status: job.status, result: job.result, error: job.error });
});

// Тестовый endpoint для проверки POST запросов
app.post('/test', express.raw({ limit: '20mb', type: '*/*' }), (req, res) => {
    console.log('=== TEST REQUEST ===');
    console.log('Body size:', req.body?.length || 0);
    res.json({ 
        success: true, 
        message: 'Test endpoint works', 
        bodySize: req.body?.length || 0,
        timestamp: Date.now()
    });
});

// Endpoint для binary data (альтернативный)
app.post('/ocr-binary', express.raw({ limit: '50mb', type: '*/*' }), (req, res) => {
    const timestamp = Date.now();
    let tempFilePath = null;
    let tempImagePath = null;
    let isAsync = false; // видим в finally
    
    console.log(`=== NEW OCR REQUEST ${timestamp} ===`);
    console.log(`Request size: ${req.body?.length || 0} bytes`);
    console.log(`Headers:`, req.headers);
    
    // Отправляем немедленный ответ что запрос получен
    res.setHeader('Content-Type', 'application/json');
    
    try {
        if (!req.body || req.body.length === 0) {
            console.log('ERROR: No binary data received');
            return res.status(400).json({ 
                success: false, 
                error: 'No binary data received' 
            });
        }

        // Поддержка асинхронного режима: ?async=1 или заголовок x-async: 1
    isAsync = req.query.async === '1' || req.headers['x-async'] === '1' || req.headers['x-async'] === 'true';

    // Детектируем тип входного файла (PDF, изображение, DOC/DOCX)
        const header5 = req.body.slice(0, 5).toString('ascii');
        const isPdf = header5 === '%PDF-';

        // Простая детекция расширения для изображений по сигнатуре
        const b0 = req.body[0];
        const b1 = req.body[1];
        const b2 = req.body[2];
        const b3 = req.body[3];
        let imageExt = 'png';
        // PNG
        if (b0 === 0x89 && b1 === 0x50 && b2 === 0x4E && b3 === 0x47) imageExt = 'png';
        // JPEG
        else if (b0 === 0xFF && b1 === 0xD8 && b2 === 0xFF) imageExt = 'jpg';
        // WEBP ('RIFF' ... 'WEBP') — упрощённо по первой сигнатуре
        else if (header5.slice(0,4) === 'RIFF') imageExt = 'webp';

    // DOC (OLE Compound): D0 CF 11 E0 ... ; DOCX (ZIP/PK): 'PK' 0x50 0x4B
    const isDocOle = (b0 === 0xD0 && b1 === 0xCF && b2 === 0x11 && b3 === 0xE0);
    const isZipPk = (b0 === 0x50 && b1 === 0x4B); // будем трактовать как DOCX

    const fileKind = isPdf ? 'pdf' : (isDocOle ? 'doc' : (isZipPk ? 'docx' : 'image'));
    const tempFileName = fileKind === 'pdf' ? `temp_${timestamp}.pdf`
                : fileKind === 'doc' ? `temp_${timestamp}.doc`
                : fileKind === 'docx' ? `temp_${timestamp}.docx`
                : `temp_${timestamp}.${imageExt}`;
        tempFilePath = `/files/uploads/${tempFileName}`;
        fs.writeFileSync(tempFilePath, req.body);
    console.log(`Binary file saved: ${tempFilePath}, size: ${req.body.length}, kind=${fileKind}`);

        // Если async-режим, возвращаем jobId и запускаем обработку в фоне
        if (isAsync) {
            const jobId = createJob();
            console.log(`Async mode enabled, jobId=${jobId}`);
            res.status(202).json({ success: true, accepted: true, jobId });

            // Фоновая обработка
            setImmediate(() => {
                try {
                    let result;
                    if (fileKind === 'pdf') {
                        result = runOcrForPdfFile(tempFilePath, timestamp, tempFileName, req.body.length);
                    } else if (fileKind === 'doc' || fileKind === 'docx') {
                        const pdfPath = convertDocToPdf(tempFilePath, timestamp);
                        result = runOcrForPdfFile(pdfPath, timestamp, pdfPath.split('/').pop(), req.body.length);
                    } else {
                        result = runOcrForImageFile(tempFilePath, timestamp, tempFileName, req.body.length);
                    }
                    setJobResult(jobId, result);
                } catch (e) {
                    console.error('Async OCR error:', e.message);
                    setJobError(jobId, e.message);
                } finally {
                    cleanupTempArtifacts(timestamp, tempFilePath);
                }
            });
            // Не продолжаем синхронный путь
            return;
        }

        // Синхронная обработка (текущий стандартный путь)
        let result;
        if (fileKind === 'pdf') {
            result = runOcrForPdfFile(tempFilePath, timestamp, tempFileName, req.body.length);
        } else if (fileKind === 'doc' || fileKind === 'docx') {
            const pdfPath = convertDocToPdf(tempFilePath, timestamp);
            result = runOcrForPdfFile(pdfPath, timestamp, pdfPath.split('/').pop(), req.body.length);
        } else {
            result = runOcrForImageFile(tempFilePath, timestamp, tempFileName, req.body.length);
        }
        res.json(result);

    } catch (error) {
        console.error('OCR Error:', error.message);
        res.json({ 
            success: false, 
            error: error.message,
            text: '',
            details: error.toString()
        });
    } finally {
        // Очистка временных артефактов: для async делаем в фоне, для sync — здесь
        if (!isAsync) {
            cleanupTempArtifacts(timestamp, tempFilePath);
        }
    }
});

// Вспомогательная функция OCR для PDF-файла (возвращает объект результата)
function runOcrForPdfFile(tempFilePath, timestamp, tempFileName, inputSize) {
    // Конвертируем PDF в изображения
    const imageBaseName = `/files/uploads/temp_${timestamp}`;
    const tempImagePath = `${imageBaseName}-%d.png`;

    console.log('Converting PDF to images...');
    execSync(`pdftoppm -png -r 300 "${tempFilePath}" "${imageBaseName}"`, { 
        timeout: 30000 
    });

    // Ищем созданные изображения
    const imageFiles = fs.readdirSync('/files/uploads')
        .filter(f => f.startsWith(`temp_${timestamp}-`) && f.endsWith('.png'))
        .sort();

    if (imageFiles.length === 0) {
        throw new Error('No images created from PDF');
    }

    console.log(`Created ${imageFiles.length} image(s), running OCR...`);

    // Обрабатываем каждое изображение через OCR
    let allText = '';
    const pages = [];
    
    for (let i = 0; i < imageFiles.length; i++) {
        const imageFile = imageFiles[i];
        const imagePath = `/files/uploads/${imageFile}`;
        try {
            const pageText = execSync(
                `tesseract "${imagePath}" stdout -l ukr+rus+eng`, 
                { 
                    encoding: 'utf8', 
                    timeout: 30000,
                    maxBuffer: 1024 * 1024
                }
            );
            
            const cleanPageText = pageText.trim();
            allText += cleanPageText + '\n\n';
            
            // Сохраняем текст каждой страницы отдельно
            pages.push({
                pageNumber: i + 1,
                text: cleanPageText,
                textLength: cleanPageText.length,
                imageFile: imageFile
            });
            
            // Удаляем обработанное изображение
            fs.unlinkSync(imagePath);
        } catch (ocrError) {
            console.log(`OCR error for ${imageFile}:`, ocrError.message);
            pages.push({
                pageNumber: i + 1,
                text: '',
                textLength: 0,
                error: ocrError.message,
                imageFile: imageFile
            });
        }
    }

    console.log(`OCR completed. Total text length: ${allText.length}, Pages: ${pages.length}`);

    return {
        success: true,
        text: allText.trim(),
        pages: pages,
        fileName: tempFileName,
        textLength: allText.trim().length,
        inputSize: inputSize,
        pagesProcessed: imageFiles.length,
        totalPages: pages.length
    };
}

// Конвертация DOC/DOCX в PDF через Gotenberg
function convertDocToPdf(inputPath, timestamp) {
    const outputPdf = `/files/uploads/temp_${timestamp}_converted.pdf`;
    console.log(`Converting DOC/DOCX to PDF via Gotenberg: ${inputPath} -> ${outputPdf}`);
    try {
        // Используем curl multipart POST
        const cmd = `sh -lc "curl -sSf -F files=@'${inputPath}' http://gotenberg:3000/forms/libreoffice/convert -o '${outputPdf}'"`;
        execSync(cmd, { timeout: 60000 });
        if (!fs.existsSync(outputPdf)) {
            throw new Error('Gotenberg did not produce output PDF');
        }
        console.log('DOC/DOCX converted to PDF successfully');
        return outputPdf;
    } catch (e) {
        console.error('Conversion error (DOC->PDF):', e.message);
        throw e;
    }
}

// OCR для одного изображения
function runOcrForImageFile(tempFilePath, timestamp, tempFileName, inputSize) {
    console.log('Running OCR on image...');
    let allText = '';
    const pages = [];
    try {
        const pageText = execSync(
            `tesseract "${tempFilePath}" stdout -l ukr+rus+eng`,
            {
                encoding: 'utf8',
                timeout: 30000,
                maxBuffer: 1024 * 1024
            }
        );
        const cleanText = pageText.trim();
        allText = cleanText;
        pages.push({ pageNumber: 1, text: cleanText, textLength: cleanText.length, imageFile: tempFileName });
    } catch (e) {
        console.log('OCR error (image):', e.message);
        pages.push({ pageNumber: 1, text: '', textLength: 0, error: e.message, imageFile: tempFileName });
    }

    console.log(`OCR (image) completed. Text length: ${allText.length}`);
    return {
        success: true,
        text: allText,
        pages,
        fileName: tempFileName,
        textLength: allText.length,
        inputSize,
        pagesProcessed: 1,
        totalPages: pages.length
    };
}

// Очистка временных файлов и изображений
function cleanupTempArtifacts(timestamp, tempFilePath) {
    // Очищаем временные файлы
    if (tempFilePath && fs.existsSync(tempFilePath)) {
        try {
            fs.unlinkSync(tempFilePath);
        } catch (e) {
            console.log('Error cleaning PDF file:', e.message);
        }
    }
    
    // Очищаем оставшиеся изображения и возможные сконвертированные PDF
    try {
        const dir = '/files/uploads';
        const remainingImages = fs.readdirSync(dir)
            .filter(f => f.startsWith(`temp_${timestamp}-`) && f.endsWith('.png'));
        
        remainingImages.forEach(img => {
            try {
                fs.unlinkSync(`${dir}/${img}`);
            } catch (e) {
                console.log(`Error cleaning image ${img}:`, e.message);
            }
        });

        // Стираем возможный сконвертированный PDF
        const extraPdfs = fs.readdirSync(dir)
            .filter(f => f.startsWith(`temp_${timestamp}`) && f.endsWith('_converted.pdf'));
        extraPdfs.forEach(pdf => {
            try {
                fs.unlinkSync(`${dir}/${pdf}`);
            } catch (e) {
                console.log(`Error cleaning converted pdf ${pdf}:`, e.message);
            }
        });
    } catch (e) {
        console.log('Error during cleanup:', e.message);
    }
}

// Увеличиваем таймауты для больших файлов
const server = app.listen(port, '0.0.0.0', () => {
    console.log(`OCR API server running on port ${port}`);
    console.log('Available endpoints:');
    console.log('  POST /ocr - multipart/form-data');
    console.log('  POST /ocr-binary - binary data (supports ?async=1 or x-async header)');
    console.log('  POST /extract-docx - extract text from DOCX (multipart)');
    console.log('  POST /extract-docx-binary - extract text from DOCX (binary)');
    console.log('  GET /result/:jobId - fetch async OCR result');
    console.log('  GET /health - health check');
});

// Устанавливаем таймауты
server.timeout = 300000; // 5 минут
server.keepAliveTimeout = 300000;
server.headersTimeout = 300000;