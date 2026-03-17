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
      session: meetSession,
    },
  });

  // Handle new-window requests (popups) - allow all in-app with same session
  mainWindow.webContents.setWindowOpenHandler(({ url: targetUrl }) => {
    return {
      action: 'allow',
      overrideBrowserWindowOptions: {
        webPreferences: {
          session: meetSession,
        },
      },
    };
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
  // Set up persistent session
  meetSession = session.fromPartition('persist:meet');

  // Strip Electron/AppName from UA so Google treats us as real Chrome
  const defaultUA = meetSession.getUserAgent();
  const cleanUA = defaultUA.replace(/\s*Electron\/[\S]+/, '').replace(/\s*g-meet\/[\S]+/, '');
  meetSession.setUserAgent(cleanUA);

  // Grant ALL Chromium-level permission requests (this is a dedicated Meet app)
  meetSession.setPermissionRequestHandler((webContents, permission, callback) => {
    callback(true);
  });

  // Permission checks must also return true or Meet silently thinks permissions are denied
  meetSession.setPermissionCheckHandler(() => true);

  // Screen sharing: bridge getDisplayMedia to Electron's desktopCapturer
  meetSession.setDisplayMediaRequestHandler((request, callback) => {
    desktopCapturer.getSources({ types: ['screen', 'window'] }).then((sources) => {
      if (sources.length > 0) {
        callback({ video: sources[0], audio: 'loopback' });
      } else {
        callback({});
      }
    }).catch(() => callback({}));
  });

  // Request macOS system-level camera and microphone permissions
  await systemPreferences.askForMediaAccess('camera');
  await systemPreferences.askForMediaAccess('microphone');

  // Screen capture: no programmatic prompt, but log status for debugging
  const screenAccess = systemPreferences.getMediaAccessStatus('screen');
  if (screenAccess !== 'granted') {
    console.log('Screen recording not granted. Enable in System Settings > Privacy & Security > Screen & System Audio Recording.');
  }

  // Load Ava extension
  const avaVersion = getLatestExtVersion(AVA_EXT_BASE);
  if (avaVersion) {
    const avaPath = path.join(AVA_EXT_BASE, avaVersion);
    try {
      await meetSession.loadExtension(avaPath);
      console.log(`Loaded Ava extension v${avaVersion}`);
    } catch (err) {
      console.error('Failed to load Ava extension:', err.message);
    }
  } else {
    console.warn('Ava extension not found in Chrome profile');
  }

  buildMenu();

  const argUrl = extractMeetUrl(process.argv);
  const url = pendingUrl || argUrl || MEET_HOME;
  pendingUrl = null;

  createWindow(url);
});
