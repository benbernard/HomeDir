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

// ─── Sharing overlay ───
let overlayWindow = null;
let overlayInterval = null;
let sharedWindowId = null;
const BORDER_WIDTH = 4;

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

// ─── Sharing overlay ───

function createOverlay() {
  if (overlayWindow) return;
  overlayWindow = new BrowserWindow({
    frame: false,
    transparent: true,
    alwaysOnTop: true,
    hasShadow: false,
    skipTaskbar: true,
    focusable: false,
    resizable: false,
    movable: false,
    show: false,
    webPreferences: { nodeIntegration: false, contextIsolation: true },
  });
  overlayWindow.setIgnoreMouseEvents(true);
  // Prevent the overlay from appearing in the macOS window switcher (Cmd-Tab)
  overlayWindow.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
  // Keep on top across spaces
  overlayWindow.setAlwaysOnTop(true, 'screen-saver');

  const borderColor = '#00ff00';
  const html = `<html><head><style>
    html,body{margin:0;padding:0;overflow:hidden;background:transparent}
    div{position:fixed;inset:0;border:${BORDER_WIDTH}px solid ${borderColor};
        box-sizing:border-box;border-radius:4px}
  </style></head><body><div></div></body></html>`;
  overlayWindow.loadURL(`data:text/html;charset=utf-8,${encodeURIComponent(html)}`);

  overlayWindow.on('closed', () => {
    overlayWindow = null;
  });
}

function updateOverlayPosition() {
  if (!overlayWindow || !sharedWindowId || !pickerNative) return;
  const bounds = pickerNative.getWindowBounds(sharedWindowId);
  if (!bounds) {
    // Window no longer exists — stop tracking
    destroyOverlay();
    return;
  }
  overlayWindow.setBounds({
    x: Math.round(bounds.x - BORDER_WIDTH),
    y: Math.round(bounds.y - BORDER_WIDTH),
    width: Math.round(bounds.width + 2 * BORDER_WIDTH),
    height: Math.round(bounds.height + 2 * BORDER_WIDTH),
  });
  if (!overlayWindow.isVisible()) overlayWindow.show();
}

function startOverlayTracking(windowId) {
  sharedWindowId = windowId;
  createOverlay();
  updateOverlayPosition();
  // Poll window position at ~15fps for smooth tracking
  overlayInterval = setInterval(updateOverlayPosition, 66);
  console.log(`[Overlay] Tracking window ${windowId}`);
}

function destroyOverlay() {
  if (overlayInterval) {
    clearInterval(overlayInterval);
    overlayInterval = null;
  }
  sharedWindowId = null;
  if (overlayWindow) {
    overlayWindow.close();
    overlayWindow = null;
  }
  console.log('[Overlay] Destroyed');
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
    // Only allow Google auth popups to open inside Meety
    if (targetUrl.includes('accounts.google.com') || targetUrl.includes('accounts.youtube.com')) {
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
    // Unwrap Google redirect URLs to open the actual destination
    try {
      const parsed = new URL(targetUrl);
      if (parsed.hostname === 'www.google.com' && parsed.pathname === '/url' && parsed.searchParams.has('url')) {
        shell.openExternal(parsed.searchParams.get('url'));
        return { action: 'deny' };
      }
    } catch {}
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
            const stream = await origGetDisplayMedia(constraints);
            const videoTrack = stream.getVideoTracks()[0];
            if (videoTrack) {
              const label = videoTrack.label || '';
              console.log('[Meety] Sharing window track label:', label);
              window.meetyShare.sharingStarted(label);
              videoTrack.addEventListener('ended', () => {
                console.log('[Meety] Window sharing track ended');
                window.meetyShare.sharingStopped();
              });
            }
            return stream;
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

function openExtensionPopup(ext) {
  const manifest = ext.manifest || {};
  const popup = manifest.action?.default_popup || manifest.browser_action?.default_popup;
  if (!popup) return;

  const popupUrl = `chrome-extension://${ext.id}/${popup}`;
  const win = new BrowserWindow({
    width: 400,
    height: 600,
    title: ext.name,
    webPreferences: {
      session: meetSession,
      sandbox: false,
    },
  });
  win.loadURL(popupUrl);
}

function buildExtensionsSubmenu() {
  if (!meetSession) return [{ label: 'No session', enabled: false }];
  const extensions = meetSession.getAllExtensions();
  if (!extensions || extensions.length === 0) {
    return [{ label: 'No extensions loaded', enabled: false }];
  }
  return extensions.map(ext => {
    const manifest = ext.manifest || {};
    const hasPopup = !!(manifest.action?.default_popup || manifest.browser_action?.default_popup);
    const hasOptions = !!(manifest.options_ui?.page || manifest.options_page);
    const submenu = [];
    if (hasPopup) {
      submenu.push({ label: 'Open Popup', click: () => openExtensionPopup(ext) });
    }
    if (hasOptions) {
      const optPage = manifest.options_ui?.page || manifest.options_page;
      submenu.push({
        label: 'Options',
        click: () => {
          const win = new BrowserWindow({
            width: 600, height: 500, title: `${ext.name} Options`,
            webPreferences: { session: meetSession, sandbox: false },
          });
          win.loadURL(`chrome-extension://${ext.id}/${optPage}`);
        },
      });
    }
    if (submenu.length === 0) {
      submenu.push({ label: 'No UI available', enabled: false });
    }
    return { label: ext.name, submenu };
  });
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
      label: 'Extensions',
      submenu: buildExtensionsSubmenu(),
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
  destroyOverlay();
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

  ipcMain.handle('meety-sharing-started', async (_event, trackLabel) => {
    console.log(`[Overlay] Sharing started, track label: "${trackLabel}"`);
    if (!pickerNative?.findWindowByTitle) {
      console.log('[Overlay] Native addon not available, skipping overlay');
      return;
    }
    const match = pickerNative.findWindowByTitle(trackLabel);
    if (match) {
      startOverlayTracking(match.id);
    } else {
      console.log(`[Overlay] Could not find window matching "${trackLabel}"`);
    }
  });

  ipcMain.handle('meety-sharing-stopped', async () => {
    console.log('[Overlay] Sharing stopped');
    destroyOverlay();
  });

  // Polyfill chrome.windows / chrome.sidePanel for extensions (unsupported in Electron).
  // We inject into every extension webContents (background service worker, etc.)
  // to replace unsupported APIs with working alternatives.
  const extWindowsById = new Map();
  let nextExtWindowId = 100;

  function openExtensionWindow(url, opts = {}) {
    const id = nextExtWindowId++;
    console.log(`[Extension] Opening window id=${id}: ${url}`);
    const win = new BrowserWindow({
      width: opts.width || 500,
      height: opts.height || 600,
      title: 'Extension',
      webPreferences: {
        session: meetSession,
        sandbox: false,
      },
    });
    win.loadURL(url);
    extWindowsById.set(id, win);
    win.on('closed', () => extWindowsById.delete(id));
    return id;
  }

  function closeExtensionWindow(id) {
    const win = extWindowsById.get(id);
    if (win && !win.isDestroyed()) win.close();
    extWindowsById.delete(id);
  }

  // Inject polyfills into extension background webContents
  app.on('web-contents-created', (_event, wc) => {
    wc.on('did-finish-load', () => {
      const url = wc.getURL();
      if (!url.startsWith('chrome-extension://')) return;

      wc.executeJavaScript(`
        (function() {
          if (window.__meetyExtPolyfilled) return;
          window.__meetyExtPolyfilled = true;

          // Polyfill chrome.windows
          if (!chrome.windows || !chrome.windows.create) {
            if (!chrome.windows) chrome.windows = {};
            chrome.windows.WINDOW_ID_NONE = -1;
          }

          const _origWindowsCreate = chrome.windows.create;
          chrome.windows.create = function(opts) {
            const url = opts?.url || '';
            console.log('[Meety Polyfill] chrome.windows.create:', url);
            // Open via window.open — Electron will catch this via setWindowOpenHandler
            window.open(url, '_blank');
            return Promise.resolve({ id: 1 });
          };

          const _origWindowsRemove = chrome.windows.remove;
          chrome.windows.remove = function(id) {
            return Promise.resolve();
          };

          chrome.windows.getLastFocused = function() {
            return Promise.resolve({ id: 1 });
          };

          // Polyfill chrome.sidePanel (no-op, not supported in Electron)
          if (!chrome.sidePanel) {
            chrome.sidePanel = {
              setPanelBehavior: () => Promise.resolve(),
              open: () => Promise.resolve(),
            };
          }

          console.log('[Meety Polyfill] Extension APIs polyfilled');
        })();
      `).catch(() => {});
    });
  });

  // Catch window.open from extension backgrounds and open as BrowserWindow.
  // Only apply to extension webContents to avoid overriding the main window handler.
  app.on('web-contents-created', (_event, wc) => {
    wc.on('did-finish-load', () => {
      if (!wc.getURL().startsWith('chrome-extension://')) return;
      wc.setWindowOpenHandler(({ url: targetUrl }) => {
        if (targetUrl.startsWith('http')) {
          openExtensionWindow(targetUrl);
          return { action: 'deny' };
        }
        return { action: 'allow' };
      });
    });
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
