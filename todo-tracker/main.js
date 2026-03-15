const { app, BrowserWindow, ipcMain, dialog } = require('electron');
const path = require('path');
const fs = require('fs');

let mainWindow;
let watchedPath = null;
let watcher = null;

// --- Config: remember the chosen todo.json path ---
function configPath() {
  return path.join(app.getPath('userData'), 'config.json');
}

function loadConfig() {
  try {
    return JSON.parse(fs.readFileSync(configPath(), 'utf-8'));
  } catch {
    return {};
  }
}

function saveConfig(cfg) {
  fs.writeFileSync(configPath(), JSON.stringify(cfg, null, 2));
}

// --- File watching ---
function startWatching(filePath) {
  stopWatching();
  watchedPath = filePath;
  try {
    watcher = fs.watch(filePath, { persistent: false }, (eventType) => {
      if (eventType === 'change' && mainWindow && !mainWindow.isDestroyed()) {
        // Debounce: small delay so writes finish
        setTimeout(() => {
          mainWindow.webContents.send('file-changed');
        }, 100);
      }
    });
  } catch {
    // File may not exist yet, that's okay
  }
}

function stopWatching() {
  if (watcher) {
    watcher.close();
    watcher = null;
  }
}

// --- IPC handlers ---
ipcMain.handle('get-remembered-path', () => {
  const cfg = loadConfig();
  if (cfg.todoFilePath && fs.existsSync(cfg.todoFilePath)) {
    return cfg.todoFilePath;
  }
  return null;
});

ipcMain.handle('pick-file', async () => {
  const result = await dialog.showOpenDialog(mainWindow, {
    title: 'Select todo.json',
    filters: [{ name: 'JSON', extensions: ['json'] }],
    properties: ['openFile'],
  });
  if (result.canceled || result.filePaths.length === 0) return null;
  const filePath = result.filePaths[0];
  saveConfig({ todoFilePath: filePath });
  startWatching(filePath);
  return filePath;
});

ipcMain.handle('read-file', async (_event, filePath) => {
  try {
    const text = fs.readFileSync(filePath, 'utf-8');
    return { ok: true, data: text };
  } catch (e) {
    return { ok: false, error: e.message };
  }
});

ipcMain.handle('write-file', async (_event, filePath, content) => {
  try {
    fs.writeFileSync(filePath, content, 'utf-8');
    return { ok: true };
  } catch (e) {
    return { ok: false, error: e.message };
  }
});

ipcMain.handle('start-watching', (_event, filePath) => {
  startWatching(filePath);
});

ipcMain.handle('change-file', async () => {
  // Forget the current file and let user pick a new one
  saveConfig({});
  stopWatching();
  return true;
});

// --- Window ---
function createWindow() {
  mainWindow = new BrowserWindow({
    width: 620,
    height: 800,
    minWidth: 400,
    minHeight: 400,
    icon: path.join(__dirname, 'icon.icns'),
    titleBarStyle: 'hiddenInset',
    trafficLightPosition: { x: 16, y: 18 },
    backgroundColor: '#f5f5f0',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  mainWindow.loadFile('index.html');
}

app.whenReady().then(() => {
  if (process.platform === 'darwin') {
    app.dock.setIcon(path.join(__dirname, 'app-icon.png'));
  }
  createWindow();
});

app.on('window-all-closed', () => {
  stopWatching();
  app.quit();
});

app.on('activate', () => {
  if (BrowserWindow.getAllWindows().length === 0) createWindow();
});

// Open external links in default browser
app.on('web-contents-created', (_event, contents) => {
  contents.setWindowOpenHandler(({ url }) => {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      require('electron').shell.openExternal(url);
    }
    return { action: 'deny' };
  });
});
