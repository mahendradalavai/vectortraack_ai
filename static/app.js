document.addEventListener('DOMContentLoaded', () => {
    // ── DOM references ─────────────────────────────────────────────────────────
    const statusDot        = document.getElementById('status-dot');
    const statusText       = document.getElementById('status-text');
    const modelBadge       = document.getElementById('model-badge');
    const pingBadge        = document.getElementById('ping-badge');

    const uploadZone       = document.getElementById('upload-zone');
    const fileInput        = document.getElementById('file-input');
    const btnProcess       = document.getElementById('btn-process');
    const sourceInput      = document.getElementById('source-input');
    const uploadIcon       = document.getElementById('upload-icon');
    const uploadPromptTitle= document.getElementById('upload-prompt-title');
    const fileTypesHint    = document.getElementById('file-types-hint');
    const mediaModeBadge   = document.getElementById('media-mode-badge');

    const valGarbage       = document.getElementById('val-garbage');
    const valRubbish       = document.getElementById('val-rubbish');
    const valConf          = document.getElementById('val-conf');
    const valTime          = document.getElementById('val-time');
    const valFrames        = document.getElementById('val-frames');
    const valTotalDet      = document.getElementById('val-total-det');
    const metricFrames     = document.getElementById('metric-frames');
    const metricTotalDet   = document.getElementById('metric-total-det');
    const noDetectionsMsg  = document.getElementById('no-detections-msg');
    const metricsGrid      = document.getElementById('metrics-grid');

    const visualizerEmpty      = document.getElementById('visualizer-empty');
    const visualizerDisplay    = document.getElementById('visualizer-display');
    const visualizerVideoDisplay = document.getElementById('visualizer-video-display');
    const mainDisplayImg       = document.getElementById('main-display-img');
    const mainDisplayVideo     = document.getElementById('main-display-video');
    const viewToggles          = document.getElementById('view-toggles');
    const btnViewAnnotated     = document.getElementById('btn-view-annotated');
    const btnViewOriginal      = document.getElementById('btn-view-original');
    const loaderOverlay        = document.getElementById('loader-overlay');
    const loadingLabel         = document.getElementById('loading-label');
    const loadingSubLabel      = document.getElementById('loading-sublabel');
    const hudTimestamp         = document.getElementById('hud-timestamp');
    const hudTimestampVideo    = document.getElementById('hud-timestamp-video');
    const logsList             = document.getElementById('logs-list');
    const vstatFrames          = document.getElementById('vstat-frames');
    const vstatDetections      = document.getElementById('vstat-detections');
    const videoStatsOverlay    = document.getElementById('video-stats-overlay');

    // ── State ──────────────────────────────────────────────────────────────────
    let selectedFile     = null;
    let currentMode      = 'image';   // 'image' | 'video'
    let originalImgUrl   = null;
    let annotatedImgUrl  = null;
    let originalVideoUrl = null;
    let annotatedVideoUrl= null;

    // ── Init ───────────────────────────────────────────────────────────────────
    checkSystemHealth();
    setInterval(checkSystemHealth, 5000);

    // ── Logging ────────────────────────────────────────────────────────────────
    function addLog(message, type = 'info-log') {
        const li = document.createElement('li');
        const ts = new Date().toLocaleTimeString();
        li.className = type;
        li.textContent = `[${ts}] ${message}`;
        logsList.appendChild(li);
        logsList.parentElement.scrollTop = logsList.parentElement.scrollHeight;
    }

    // ── Health Check ───────────────────────────────────────────────────────────
    async function checkSystemHealth() {
        const t0 = Date.now();
        try {
            const res = await fetch('/health');
            const latency = Date.now() - t0;
            if (res.ok) {
                const data = await res.json();
                statusDot.className  = 'status-dot online pulsing';
                statusText.textContent = 'ONLINE';
                statusText.style.color = 'var(--neon-green)';
                modelBadge.textContent = `YOLOv8: ${data.model_name}`;
                pingBadge.textContent  = `Latency: ${latency} ms`;
            } else throw new Error('API unstable');
        } catch {
            statusDot.className  = 'status-dot offline pulsing';
            statusText.textContent = 'OFFLINE';
            statusText.style.color = 'var(--neon-red)';
            modelBadge.textContent = 'YOLOv8: Disconnected';
            pingBadge.textContent  = 'Latency: -- ms';
            addLog('System health check failed: Cannot reach FastAPI backend.', 'error-log');
        }
    }

    // ── Tab Switching ──────────────────────────────────────────────────────────
    window.switchTab = function(mode) {
        currentMode  = mode;
        selectedFile = null;
        btnProcess.disabled = true;

        document.getElementById('tab-image').classList.toggle('active', mode === 'image');
        document.getElementById('tab-video').classList.toggle('active', mode === 'video');

        if (mode === 'image') {
            fileInput.accept = 'image/*';
            uploadIcon.className = 'fa-solid fa-cloud-arrow-up upload-icon';
            uploadPromptTitle.textContent = 'Drag & Drop Image Here';
            fileTypesHint.textContent = 'Supports JPG, PNG, WEBP up to 10MB';
            mediaModeBadge.innerHTML = '<i class="fa-solid fa-image"></i> IMAGE';
        } else {
            fileInput.accept = 'video/*';
            uploadIcon.className = 'fa-solid fa-film upload-icon';
            uploadPromptTitle.textContent = 'Drag & Drop Video Here';
            fileTypesHint.textContent = 'Supports MP4, AVI, MOV, MKV, WEBM';
            mediaModeBadge.innerHTML = '<i class="fa-solid fa-film"></i> VIDEO';
        }
        // Reset upload zone label
        uploadPromptTitle.textContent = mode === 'image' ? 'Drag & Drop Image Here' : 'Drag & Drop Video Here';
        addLog(`Mode switched to: ${mode.toUpperCase()}`, 'info-log');
    };

    // ── Drag and Drop ──────────────────────────────────────────────────────────
    ['dragenter', 'dragover'].forEach(ev => {
        uploadZone.addEventListener(ev, e => { e.preventDefault(); uploadZone.classList.add('dragover'); }, false);
    });
    ['dragleave', 'drop'].forEach(ev => {
        uploadZone.addEventListener(ev, e => { e.preventDefault(); uploadZone.classList.remove('dragover'); }, false);
    });
    uploadZone.addEventListener('drop', e => {
        const files = e.dataTransfer.files;
        if (files.length > 0) handleFileSelect(files[0]);
    });
    fileInput.addEventListener('change', e => {
        if (e.target.files.length > 0) handleFileSelect(e.target.files[0]);
    });

    // ── File Selection ─────────────────────────────────────────────────────────
    function handleFileSelect(file) {
        const isImage = file.type.startsWith('image/');
        const isVideo = file.type.startsWith('video/');

        if (!isImage && !isVideo) {
            addLog('Rejected: Only image or video files are supported.', 'error-log');
            return;
        }

        // Auto-switch tab to match file type
        if (isImage && currentMode !== 'image') window.switchTab('image');
        if (isVideo && currentMode !== 'video') window.switchTab('video');

        selectedFile = file;
        btnProcess.disabled = false;
        addLog(`File selected: ${file.name} (${(file.size / 1024).toFixed(1)} KB)`, 'info-log');

        uploadPromptTitle.textContent = `File Ready: ${file.name.length > 28 ? file.name.substring(0, 28) + '...' : file.name}`;

        if (isImage) {
            // Preview image locally before running detection
            const reader = new FileReader();
            reader.onload = e => {
                mainDisplayImg.src = e.target.result;
                hideAll();
                visualizerDisplay.classList.remove('hidden');
                viewToggles.classList.add('hidden');
                hudTimestamp.textContent = `GPS LOCK: PREVIEW | SOURCE: Local`;
            };
            reader.readAsDataURL(file);
        } else {
            // Preview video locally before running detection
            const url = URL.createObjectURL(file);
            mainDisplayVideo.src = url;
            mainDisplayVideo.load();
            hideAll();
            visualizerVideoDisplay.classList.remove('hidden');
            viewToggles.classList.add('hidden');
            videoStatsOverlay.classList.add('hidden');
            hudTimestampVideo.textContent = `GPS LOCK: VIDEO PREVIEW | SOURCE: Local`;
        }
    }

    function hideAll() {
        visualizerEmpty.classList.add('hidden');
        visualizerDisplay.classList.add('hidden');
        visualizerVideoDisplay.classList.add('hidden');
    }

    // ── Run Detections ─────────────────────────────────────────────────────────
    btnProcess.addEventListener('click', async () => {
        if (!selectedFile) return;
        const isVideo = currentMode === 'video';

        loaderOverlay.classList.remove('hidden');
        btnProcess.disabled = true;
        loadingLabel.textContent   = isVideo
            ? 'PROCESSING VIDEO — RUNNING YOLOv8 PER FRAME...'
            : 'RUNNING YOLOv8 SPATIAL INFERENCE...';
        loadingSubLabel.textContent = isVideo
            ? 'This may take a moment depending on video length.'
            : '';

        addLog(`Initiating YOLOv8 ${isVideo ? 'video' : 'image'} scan for ${selectedFile.name}...`, 'info-log');

        const startTime = Date.now();
        const formData  = new FormData();
        formData.append('file', selectedFile);
        formData.append('source', sourceInput.value);
        formData.append('conf', '0.10');
        formData.append('iou',  '0.45');

        const endpoint = isVideo ? '/detect/video' : '/detect/image';

        try {
            const response = await fetch(endpoint, { method: 'POST', body: formData });
            const duration = ((Date.now() - startTime) / 1000).toFixed(2);

            if (!response.ok) {
                const err = await response.json();
                throw new Error(err.detail || 'Inference engine failure.');
            }

            const result = await response.json();

            if (result.success) {
                addLog(`Scan completed in ${duration}s. ${result.message}`, 'success-log');

                if (isVideo) {
                    handleVideoResult(result, duration);
                } else {
                    handleImageResult(result, duration);
                }
            } else {
                throw new Error(result.message || 'Detection failed');
            }

        } catch (err) {
            addLog(`Error: ${err.message}`, 'error-log');
            alert(`Detection Scan Failed:\n${err.message}`);
        } finally {
            loaderOverlay.classList.add('hidden');
            btnProcess.disabled = false;
        }
    });

    // ── Image Result Handler ───────────────────────────────────────────────────
    function handleImageResult(result, duration) {
        originalImgUrl  = result.original_image_url;
        annotatedImgUrl = result.result_image_url || result.original_image_url;

        mainDisplayImg.src = annotatedImgUrl;
        hideAll();
        visualizerDisplay.classList.remove('hidden');
        viewToggles.classList.remove('hidden');
        btnViewAnnotated.classList.add('active');
        btnViewOriginal.classList.remove('active');

        const dateStr = new Date().toISOString().replace('T', ' ').substring(0, 19);
        hudTimestamp.textContent = `GPS LOCK: 37.7749° N, 122.4194° W | SOURCE: ${result.source.toUpperCase()} | TIME: ${dateStr}`;

        // Compute metrics
        let garbageCount = 0, rubbishCount = 0, maxConf = 0;
        result.detections.forEach(det => {
            const cls = det.class.toLowerCase();
            if (cls === 'garbage') garbageCount++;
            if (cls === 'rubbish') rubbishCount++;
            if (det.confidence > maxConf) maxConf = det.confidence;
            addLog(`Detected [${det.class}] at ${(det.confidence * 100).toFixed(0)}% confidence`, 'success-log');
        });
        if (result.detections.length === 0) {
            addLog('No garbage/rubbish signatures detected in this scan.', 'warning-log');
        }

        // Update metrics panel
        valGarbage.textContent = garbageCount;
        valRubbish.textContent = rubbishCount;
        valConf.textContent    = `${(maxConf * 100).toFixed(0)}%`;
        valTime.textContent    = `${duration}s`;
        metricFrames.classList.add('hidden');
        metricTotalDet.classList.add('hidden');

        noDetectionsMsg.classList.add('hidden');
        metricsGrid.classList.remove('hidden');
    }

    // ── Video Result Handler ───────────────────────────────────────────────────
    function handleVideoResult(result, duration) {
        originalVideoUrl  = result.original_video_url;
        annotatedVideoUrl = result.result_video_url || result.original_video_url;

        // Load the annotated video
        mainDisplayVideo.src = annotatedVideoUrl + '?t=' + Date.now();
        mainDisplayVideo.load();

        hideAll();
        visualizerVideoDisplay.classList.remove('hidden');

        // Show toggle — Annotated vs Original
        viewToggles.classList.remove('hidden');
        btnViewAnnotated.classList.add('active');
        btnViewOriginal.classList.remove('active');

        const dateStr = new Date().toISOString().replace('T', ' ').substring(0, 19);
        hudTimestampVideo.textContent = `GPS LOCK: 37.7749° N, 122.4194° W | SOURCE: ${result.source.toUpperCase()} | TIME: ${dateStr}`;

        // Video stats overlay
        vstatFrames.textContent     = `${result.frames_processed} frames scanned`;
        vstatDetections.textContent = `${result.total_detections} detections`;
        videoStatsOverlay.classList.remove('hidden');

        // Compute class counts
        const classCounts = result.class_counts || {};
        const garbageCount = classCounts['garbage'] || 0;
        const rubbishCount = classCounts['rubbish'] || 0;
        let maxConf = 0;
        result.detections.forEach(det => {
            if (det.confidence > maxConf) maxConf = det.confidence;
        });

        // Log per-class summary
        if (result.total_detections > 0) {
            Object.entries(classCounts).forEach(([cls, count]) => {
                addLog(`[${cls.toUpperCase()}] detected ${count} time(s) across video`, 'success-log');
            });
        } else {
            addLog('No garbage/rubbish detected in video frames.', 'warning-log');
        }
        addLog(`Frames processed: ${result.frames_processed} / ${result.total_frames || '?'}`, 'info-log');

        // Update metrics panel
        valGarbage.textContent  = garbageCount;
        valRubbish.textContent  = rubbishCount;
        valConf.textContent     = `${(maxConf * 100).toFixed(0)}%`;
        valTime.textContent     = `${duration}s`;
        valFrames.textContent   = result.frames_processed;
        valTotalDet.textContent = result.total_detections;
        metricFrames.classList.remove('hidden');
        metricTotalDet.classList.remove('hidden');

        noDetectionsMsg.classList.add('hidden');
        metricsGrid.classList.remove('hidden');
    }

    // ── View Toggles (Image) ───────────────────────────────────────────────────
    btnViewAnnotated.addEventListener('click', () => {
        if (currentMode === 'image' && annotatedImgUrl) {
            mainDisplayImg.src = annotatedImgUrl;
            btnViewAnnotated.classList.add('active');
            btnViewOriginal.classList.remove('active');
            addLog('Display: Annotated view', 'info-log');
        } else if (currentMode === 'video' && annotatedVideoUrl) {
            mainDisplayVideo.src = annotatedVideoUrl + '?t=' + Date.now();
            mainDisplayVideo.load();
            btnViewAnnotated.classList.add('active');
            btnViewOriginal.classList.remove('active');
            addLog('Display: Annotated video', 'info-log');
        }
    });

    btnViewOriginal.addEventListener('click', () => {
        if (currentMode === 'image' && originalImgUrl) {
            mainDisplayImg.src = originalImgUrl;
            btnViewOriginal.classList.add('active');
            btnViewAnnotated.classList.remove('active');
            addLog('Display: Original image', 'info-log');
        } else if (currentMode === 'video' && originalVideoUrl) {
            mainDisplayVideo.src = originalVideoUrl + '?t=' + Date.now();
            mainDisplayVideo.load();
            btnViewOriginal.classList.add('active');
            btnViewAnnotated.classList.remove('active');
            addLog('Display: Original video', 'info-log');
        }
    });
});
