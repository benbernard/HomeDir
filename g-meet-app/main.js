const { app, BrowserWindow, shell, session, Menu, systemPreferences, desktopCapturer } = require('electron');
const path = require('path');
const fs = require('fs');

const MEET_HOME = 'https://meet.google.com';

// Ava extension from Chrome Default profile
const AVA_EXT_BASE = path.join(
  app.getPath('home'),
  'Library/Application Support/Google/Chrome/Default/Extensions/klckgebpahapdbhmncaioebjcffalafc'
);

let meetSession = null;
let mainWindow = null;
let pendingUrl = null;

// ─── CRITICAL FIX 1: Chromium flags must be set BEFORE app is ready ───
// These enable features that Google Meet checks for
app.commandLine.appendSwitch('enable-features', 'WebRTCPipeWireCapturer');
// Use the legacy screen-audio permission model if CoreAudio Tap causes issues (Electron 39+)
// Uncomment the next line if desktop audio capture doesn't work on macOS 14.2+:
// app.commandLine.appendSwitch('disable-features', 'MacCatapLoopbackAudioForScreenShare');

// Register as handler for gmeet:// protocol (for dev mode)
if (!app.isDefaultProtocolClient('gmeet')) {
  app.setAsDefaultProtocolClient('gmeet');
}

function meetUrlFromArg(arg) {
  if (!arg) return null;

  if (arg.startsWith('gmeet://')) {
    const stripped = arg.replace('gmeet://', '');
    if (stripped.startsWith('meet.google.com')) {
      return `https://${stripped}`;
    }
    return `https://meet.google.com/${stripped.replace(/^\/+/, '')}`;
  }

  if (arg.startsWith('https://meet.google.com')) {
    return arg;
  }

  if (/^[a-z]{3}-[a-z]{4}-[a-z]{3}$/.test(arg)) {
    return `https://meet.google.com/${arg}`;
  }

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
  } catch {
    return null;
  }
}

function createWindow(url) {
  mainWindow = new BrowserWindow({
    width: 1280,
    height: 800,
    title: 'Meety',
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      sandbox: false, // CRITICAL FIX 2: sandbox must be false for media permissions to flow correctly
      session: meetSession,
    },
  });

  // Handle new-window requests (popups) - allow all in-app with same session
  mainWindow.webContents.setWindowOpenHandler(({ url: targetUrl }) => {
    // Google auth popups and Meet-related URLs should open in-app
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
    // Everything else opens in the default browser
    shell.openExternal(targetUrl);
    return { action: 'deny' };
  });

  // ─── CRITICAL FIX 3: Handle in-page permission requests via webContents ───
  // Some permission requests come through the webContents directly
  mainWindow.webContents.session.setPermissionRequestHandler((webContents, permission, callback, details) => {
    console.log(`[Permission Request] ${permission}`, details?.mediaTypes || '');
    callback(true);
  });

  mainWindow.webContents.session.setPermissionCheckHandler((webContents, permission, requestingOrigin, details) => {
    console.log(`[Permission Check] ${permission} from ${requestingOrigin}`, details?.mediaType || '');
    return true;
  });

  mainWindow.loadURL(url || MEET_HOME);

  mainWindow.on('closed', () => {
    mainWindow = null;
  });

  return mainWindow;
}

function showOrCreate(url) {
  if (mainWindow) {
    if (url) {
      mainWindow.loadURL(url);
    }
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
        {
          label: 'New Window',
          accelerator: 'CmdOrCtrl+N',
          click: () => createWindow(MEET_HOME),
        },
        { role: 'close' },
      ],
    },
    {
      label: 'Edit',
      submenu: [
        { role: 'undo' },
        { role: 'redo' },
        { type: 'separator' },
        { role: 'cut' },
        { role: 'copy' },
        { role: 'paste' },
        { role: 'selectAll' },
      ],
    },
    {
      label: 'View',
      submenu: [
        { role: 'reload' },
        { role: 'forceReload' },
        { role: 'toggleDevTools' },
        { type: 'separator' },
        { role: 'resetZoom' },
        { role: 'zoomIn' },
        { role: 'zoomOut' },
        { type: 'separator' },
        { role: 'togglefullscreen' },
      ],
    },
    {
      label: 'Window',
      submenu: [
        { role: 'minimize' },
        { role: 'zoom' },
        { type: 'separator' },
        { role: 'front' },
      ],
    },
  ];

  Menu.setApplicationMenu(Menu.buildFromTemplate(template));
}

// macOS: handle open-url event (from `open` CLI or protocol handler)
app.on('open-url', (event, url) => {
  event.preventDefault();
  const meetUrl = meetUrlFromArg(url);
  if (app.isReady()) {
    showOrCreate(meetUrl || MEET_HOME);
  } else {
    pendingUrl = meetUrl;
  }
});

// macOS: re-create window when clicking dock icon
app.on('activate', () => {
  showOrCreate(null);
});

// Prevent quitting when all windows close (macOS behavior)
app.on('window-all-closed', () => {
  // Don't quit - stay in dock so we can reopen
});

// Handle second-instance (if single instance lock is held)
const gotLock = app.requestSingleInstanceLock();
if (!gotLock) {
  app.quit();
} else {
  app.on('second-instance', (_event, argv) => {
    const url = extractMeetUrl(argv);
    showOrCreate(url ? url : null);
  });
}

app.whenReady().then(async () => {
  // ─── macOS permissions: log status only ───
  // Don't call askForMediaAccess() — in dev mode it attributes the request to
  // the parent terminal (e.g. Ghostty) rather than the Electron app.
  // Chromium itself will trigger the OS permission prompt when Meet calls
  // getUserMedia(), correctly attributing it to the app binary.
  if (process.platform === 'darwin') {
    const camStatus = systemPreferences.getMediaAccessStatus('camera');
    const micStatus = systemPreferences.getMediaAccessStatus('microphone');
    const screenStatus = systemPreferences.getMediaAccessStatus('screen');
    console.log(`[Permissions] Camera: ${camStatus}, Microphone: ${micStatus}, Screen: ${screenStatus}`);

    if (screenStatus !== 'granted') {
      console.log('[Permissions] Screen recording not granted.');
      console.log('[Permissions]   Enable in: System Settings > Privacy & Security > Screen & System Audio Recording');
    }
  }

  // ─── Set up persistent session ───
  meetSession = session.fromPartition('persist:meet');

  // ─── CRITICAL FIX 5: User-agent must perfectly mimic Chrome ───
  // Google Meet checks the UA string and disables features (especially screen
  // sharing) if it detects a non-Chrome browser. We need to strip both the
  // "Electron/x.x.x" and the app name tokens.
  const defaultUA = meetSession.getUserAgent();
  const cleanUA = defaultUA
    .replace(/\s*Electron\/[\S]+/, '')
    .replace(/\s*g-meet\/[\S]+/, '')
    .replace(/\s*Meety\/[\S]+/, '');
  meetSession.setUserAgent(cleanUA);
  console.log(`[UA] Set user agent to: ${cleanUA}`);

  // ─── CRITICAL FIX 6: Permission handlers on the session object ───
  // Both handlers MUST be set on the same session object used by the BrowserWindow.
  // The permission REQUEST handler is called when a web page calls getUserMedia() etc.
  // The permission CHECK handler is called when the page queries permissions.query().
  meetSession.setPermissionRequestHandler((webContents, permission, callback, details) => {
    console.log(`[Session Permission Request] ${permission}`, JSON.stringify(details || {}));
    // Grant everything for meet.google.com
    callback(true);
  });

  meetSession.setPermissionCheckHandler((webContents, permission, requestingOrigin, details) => {
    console.log(`[Session Permission Check] ${permission} from ${requestingOrigin}`);
    // Return true for all permission checks
    return true;
  });

  // ─── CRITICAL FIX 7: Screen sharing with setDisplayMediaRequestHandler ───
  // This is the ONLY way to make getDisplayMedia() work in Electron.
  // Google Meet calls navigator.mediaDevices.getDisplayMedia() which Electron
  // does NOT natively support — it must be bridged through desktopCapturer.
  //
  // On macOS 15+ with Electron 32+, useSystemPicker: true enables the native
  // macOS screen picker, which is the most reliable approach.
  meetSession.setDisplayMediaRequestHandler(async (request, callback) => {
    console.log('[Screen Share] Display media requested');
    try {
      const sources = await desktopCapturer.getSources({
        types: ['screen', 'window'],
        thumbnailSize: { width: 0, height: 0 }, // Skip thumbnails for speed
      });
      console.log(`[Screen Share] Found ${sources.length} sources`);

      if (sources.length > 0) {
        // Provide the first screen source. The system picker (if enabled via
        // useSystemPicker) will override this and show the native macOS picker.
        callback({ video: sources[0], audio: 'loopback' });
      } else {
        console.warn('[Screen Share] No sources found — is Screen Recording permission granted?');
        callback({});
      }
    } catch (err) {
      console.error('[Screen Share] Error getting sources:', err);
      callback({});
    }
  }, { useSystemPicker: true }); // Use native macOS picker when available (macOS 15+)

  // ─── Load Ava extension ───
  const avaVersion = getLatestExtVersion(AVA_EXT_BASE);
  if (avaVersion) {
    const avaPath = path.join(AVA_EXT_BASE, avaVersion);
    try {
      await meetSession.loadExtension(avaPath);
      console.log(`[Extension] Loaded Ava extension v${avaVersion}`);
    } catch (err) {
      console.error('[Extension] Failed to load Ava extension:', err.message);
    }
  } else {
    console.warn('[Extension] Ava extension not found in Chrome profile');
  }

  buildMenu();

  const argUrl = extractMeetUrl(process.argv);
  const url = pendingUrl || argUrl || MEET_HOME;
  pendingUrl = null;

  createWindow(url);
});
