const { app, BrowserWindow, shell, session, Menu, systemPreferences, desktopCapturer, ipcMain } = require('electron');
const path = require('path');
const fs = require('fs');

// Native picker addon — only needed as diagnostic fallback; Electron 32+
// on macOS 15+ handles the system picker internally via useSystemPicker.
let pickerNative;
try {
  pickerNative = require('./build/Release/picker_config.node');
  // Immediately clear any stale sharing session left over from a previous
  // crash or unclean exit — prevents the macOS "Currently Sharing" indicator
  // from persisting and interfering with new sharing sessions.
  if (pickerNative.cleanupPicker) {
    pickerNative.cleanupPicker();
  }
  console.log('[Native] Loaded picker_config addon (cleared stale state)');
} catch (err) {
  console.log('[Native] picker_config addon not available (not needed on macOS 15+)');
}

const MEET_HOME = 'https://meet.google.com';

const AVA_EXT_BASE = path.join(
  app.getPath('home'),
  'Library/Application Support/Google/Chrome/Default/Extensions/klckgebpahapdbhmncaioebjcffalafc'
);

const EXTENSIONS_BASE = path.join(
  app.getPath('home'),
  'Library/Application Support/Google/Chrome/Default/Extensions'
);

let meetSession = null;
let mainWindow = null;
let pendingUrl = null;

app.commandLine.appendSwitch('enable-features', 'WebRTCPipeWireCapturer');

if (!app.isDefaultProtocolClient('gmeet')) {
  app.setAsDefaultProtocolClient('gmeet');
}

// ─── IPC for picker ───

ipcMain.handle('picker-get-sources', async (event, type) => {
  const sources = await desktopCapturer.getSources({
    types: [type],
    thumbnailSize: { width: 240, height: 135 },
  });
  return sources.map(s => ({ id: s.id, name: s.name, thumbnail: s.thumbnail.toDataURL() }));
});

// ─── URL helpers ───

function meetUrlFromArg(arg) {
  if (!arg) return null;
  if (arg.startsWith('gmeet://')) {
    const stripped = arg.replace('gmeet://', '');
    if (stripped.startsWith('meet.google.com')) return `https://${stripped}`;
    return `https://meet.google.com/${stripped.replace(/^\/+/, '')}`;
  }
  if (arg.startsWith('https://meet.google.com')) return arg;
  if (/^[a-z]{3}-[a-z]{4}-[a-z]{3}$/.test(arg)) return `https://meet.google.com/${arg}`;
  return null;
}

function extractMeetUrl(argv) {
  for (const arg of argv) {
    const url = meetUrlFromArg(arg);
    if (url) return url;
  }
  return null;
}

function getLatestExtVersion(basePath) {
  try {
    const versions = fs.readdirSync(basePath).filter(d => !d.startsWith('.'));
    versions.sort();
    return versions[versions.length - 1];
  } catch { return null; }
}

// ─── Share picker ───

function showSharePicker() {
  return new Promise((resolve) => {
    const pickerWin = new BrowserWindow({
      width: 420,
      height: 340,
      parent: mainWindow,
      modal: true,
      show: false,
      resizable: true,
      minimizable: false,
      maximizable: false,
      title: 'Share your screen',
      webPreferences: {
        nodeIntegration: false,
        contextIsolation: true,
        sandbox: true,
        preload: path.join(__dirname, 'picker-preload.js'),
      },
    });

    let resolved = false;
    function finish(result) {
      if (resolved) return;
      resolved = true;
      ipcMain.removeAllListeners('picker-select');
      ipcMain.removeAllListeners('picker-cancel');
      ipcMain.removeAllListeners('picker-show-sources');
      ipcMain.removeAllListeners('picker-use-system');
      pickerWin.close();
      resolve(result);
    }

    ipcMain.once('picker-select', (event, sourceId) => finish(sourceId));
    ipcMain.once('picker-cancel', () => finish(null));
    ipcMain.once('picker-use-system', () => finish('__system_picker__'));

    // User chose a category → expand window and show thumbnails
    ipcMain.once('picker-show-sources', async (event, type) => {
      pickerWin.setSize(820, 520, true);
      pickerWin.center();
      const sources = await desktopCapturer.getSources({
        types: [type],
        thumbnailSize: { width: 240, height: 135 },
      });
      // Filter out our own picker window and Meety itself for window sources
      const filtered = type === 'window'
        ? sources.filter(s => s.name !== 'Share your screen')
        : sources;
      const data = filtered.map(s => ({ id: s.id, name: s.name, thumbnail: s.thumbnail.toDataURL() }));
      pickerWin.webContents.executeJavaScript(
        `window.showSources(${JSON.stringify(data)});`
      );
    });

    pickerWin.on('closed', () => {
      ipcMain.removeAllListeners('picker-select');
      ipcMain.removeAllListeners('picker-cancel');
      ipcMain.removeAllListeners('picker-show-sources');
      ipcMain.removeAllListeners('picker-use-system');
      if (!resolved) {
        resolved = true;
        resolve(null);
      }
    });

    pickerWin.loadFile('picker.html');
    pickerWin.once('ready-to-show', () => pickerWin.show());
  });
}

// ─── Window management ───

function createWindow(url) {
  mainWindow = new BrowserWindow({
    width: 1280,
    height: 800,
    title: 'Meety',
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      sandbox: false,
      session: meetSession,
      preload: path.join(__dirname, 'preload.js'),
    },
  });

  mainWindow.webContents.setWindowOpenHandler(({ url: targetUrl }) => {
    if (targetUrl.includes('google.com') || targetUrl.includes('accounts.google.com')) {
      return {
        action: 'allow',
        overrideBrowserWindowOptions: {
          webPreferences: {
            session: meetSession,
            sandbox: false,
          },
        },
      };
    }
    shell.openExternal(targetUrl);
    return { action: 'deny' };
  });

  mainWindow.webContents.session.setPermissionRequestHandler((wc, permission, callback, details) => {
    console.log(`[Permission Request] ${permission}`, details?.mediaTypes || '');
    callback(true);
  });

  mainWindow.webContents.session.setPermissionCheckHandler((wc, permission, requestingOrigin, details) => {
    return true;
  });

  mainWindow.webContents.on('console-message', (event) => {
    const msg = event.message;
    if (msg && !msg.includes('DevTools')) {
      console.log('[Page]', msg);
    }
  });

  // Inject getDisplayMedia interceptor. Shows our custom picker BEFORE
  // the real call fires. Handler is registered ONCE (useSystemPicker) and
  // NEVER swapped — "Entire Screen" bypasses it entirely via getUserMedia.
  mainWindow.webContents.on('did-finish-load', () => {
    mainWindow.webContents.executeJavaScript(`
      (function() {
        if (window.__meetyInterceptorInstalled) return;
        window.__meetyInterceptorInstalled = true;

        const origGetDisplayMedia = navigator.mediaDevices.getDisplayMedia.bind(navigator.mediaDevices);

        navigator.mediaDevices.getDisplayMedia = async function(constraints) {
          const choice = await window.meetyShare.showPicker();

          if (!choice) {
            throw new DOMException('Permission denied', 'NotAllowedError');
          }

          if (choice === '__system_picker__') {
            // "Application Window" → let the real getDisplayMedia through.
            // Handler has useSystemPicker: true → native macOS picker appears.
            console.log('[Meety] Application Window → system picker');
            return origGetDisplayMedia(constraints);
          }

          // "Entire Screen" → bypass getDisplayMedia entirely.
          // Use getUserMedia with chromeMediaSource to capture the chosen
          // screen directly. No handler involved, no handler swap needed.
          console.log('[Meety] Entire Screen → getUserMedia chromeMediaSource:', choice);
          return navigator.mediaDevices.getUserMedia({
            audio: false,
            video: {
              mandatory: {
                chromeMediaSource: 'desktop',
                chromeMediaSourceId: choice
              }
            }
          });
        };

        console.log('[Meety] getDisplayMedia interceptor installed');
      })();
    `).catch(err => console.error('[Meety] Failed to install interceptor:', err.message));
  });

  mainWindow.loadURL(url || MEET_HOME);

  mainWindow.on('closed', () => {
    mainWindow = null;
  });

  return mainWindow;
}

function showOrCreate(url) {
  if (mainWindow) {
    if (url) mainWindow.loadURL(url);
    mainWindow.show();
    mainWindow.focus();
  } else {
    createWindow(url);
  }
}

function buildMenu() {
  const template = [
    {
      label: app.name,
      submenu: [
        { role: 'about' },
        { type: 'separator' },
        { role: 'hide' },
        { role: 'hideOthers' },
        { role: 'unhide' },
        { type: 'separator' },
        { role: 'quit' },
      ],
    },
    {
      label: 'File',
      submenu: [
        { label: 'New Window', accelerator: 'CmdOrCtrl+N', click: () => createWindow(MEET_HOME) },
        { role: 'close' },
      ],
    },
    {
      label: 'Edit',
      submenu: [
        { role: 'undo' }, { role: 'redo' }, { type: 'separator' },
        { role: 'cut' }, { role: 'copy' }, { role: 'paste' }, { role: 'selectAll' },
      ],
    },
    {
      label: 'View',
      submenu: [
        { role: 'reload' }, { role: 'forceReload' }, { role: 'toggleDevTools' },
        { type: 'separator' },
        { role: 'resetZoom' }, { role: 'zoomIn' }, { role: 'zoomOut' },
        { type: 'separator' },
        { role: 'togglefullscreen' },
      ],
    },
    {
      label: 'Window',
      submenu: [
        { role: 'minimize' }, { role: 'zoom' }, { type: 'separator' }, { role: 'front' },
      ],
    },
  ];
  Menu.setApplicationMenu(Menu.buildFromTemplate(template));
}

// ─── App lifecycle ───

app.on('open-url', (event, url) => {
  event.preventDefault();
  const meetUrl = meetUrlFromArg(url);
  if (app.isReady()) showOrCreate(meetUrl || MEET_HOME);
  else pendingUrl = meetUrl;
});

app.on('activate', () => showOrCreate(null));
app.on('window-all-closed', () => {});

// Clean up native picker state on quit if the addon was loaded,
// so macOS releases any sharing session (menu bar indicator, audio routing).
app.on('will-quit', () => {
  if (pickerNative?.cleanupPicker) {
    pickerNative.cleanupPicker();
  }
});

const gotLock = app.requestSingleInstanceLock();
if (!gotLock) {
  app.quit();
} else {
  app.on('second-instance', (_event, argv) => {
    showOrCreate(extractMeetUrl(argv) || null);
  });
}

app.whenReady().then(async () => {
  if (process.platform === 'darwin') {
    const camStatus = systemPreferences.getMediaAccessStatus('camera');
    const micStatus = systemPreferences.getMediaAccessStatus('microphone');
    const screenStatus = systemPreferences.getMediaAccessStatus('screen');
    console.log(`[Permissions] Camera: ${camStatus}, Microphone: ${micStatus}, Screen: ${screenStatus}`);

    if (screenStatus !== 'granted') {
      console.log('[Permissions] Screen recording not granted — triggering system prompt...');
      try {
        await desktopCapturer.getSources({ types: ['screen'], thumbnailSize: { width: 0, height: 0 } });
      } catch (e) {}
    }
  }

  meetSession = session.fromPartition('persist:meet');

  const defaultUA = meetSession.getUserAgent();
  const cleanUA = defaultUA
    .replace(/\s*Electron\/[\S]+/, '')
    .replace(/\s*g-meet\/[\S]+/, '')
    .replace(/\s*Meety\/[\S]+/, '');
  meetSession.setUserAgent(cleanUA);
  console.log(`[UA] ${cleanUA}`);

  meetSession.setPermissionRequestHandler((wc, permission, callback, details) => {
    callback(true);
  });
  meetSession.setPermissionCheckHandler(() => true);

  // ─── Screen sharing ───
  // Register ONCE with useSystemPicker and NEVER change it.
  // The interceptor in the page decides which path to take:
  //   • "Entire Screen" → getUserMedia with chromeMediaSource (bypasses handler entirely)
  //   • "Application Window" → origGetDisplayMedia → system picker (via useSystemPicker)
  //   • Cancelled → interceptor throws NotAllowedError, nothing reaches the handler
  meetSession.setDisplayMediaRequestHandler((request, callback) => {
    // Fallback — only called if the system picker is unavailable
    console.log('[Screen Share] Fallback handler called (system picker unavailable)');
    callback({});
  }, { useSystemPicker: true });

  // IPC handlers for the preload/interceptor
  ipcMain.handle('meety-show-picker', async () => {
    return await showSharePicker();
  });

  // Load extensions
  const avaVersion = getLatestExtVersion(AVA_EXT_BASE);
  if (avaVersion) {
    const avaPath = path.join(AVA_EXT_BASE, avaVersion);
    try {
      await meetSession.loadExtension(avaPath);
      console.log(`[Extension] Loaded Ava v${avaVersion}`);
    } catch (err) {
      console.error('[Extension] Ava failed:', err.message);
    }
  }

  // Load MuteMe extension
  const muteExtId = 'iabboefdfnocmnkmoejbmacffgfafbbf';
  const muteExtBase = path.join(EXTENSIONS_BASE, muteExtId);
  const muteExtVersion = getLatestExtVersion(muteExtBase);
  if (muteExtVersion) {
    try {
      await meetSession.loadExtension(path.join(muteExtBase, muteExtVersion));
      console.log(`[Extension] Loaded MuteMe v${muteExtVersion}`);
    } catch (err) {
      console.error('[Extension] MuteMe failed:', err.message);
    }
  }

  buildMenu();

  const argUrl = extractMeetUrl(process.argv);
  createWindow(pendingUrl || argUrl || MEET_HOME);
  pendingUrl = null;
});
