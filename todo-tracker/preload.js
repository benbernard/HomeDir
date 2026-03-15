const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('todoAPI', {
  getRememberedPath: () => ipcRenderer.invoke('get-remembered-path'),
  pickFile: () => ipcRenderer.invoke('pick-file'),
  readFile: (path) => ipcRenderer.invoke('read-file', path),
  writeFile: (path, content) => ipcRenderer.invoke('write-file', path, content),
  startWatching: (path) => ipcRenderer.invoke('start-watching', path),
  changeFile: () => ipcRenderer.invoke('change-file'),
  onFileChanged: (callback) => {
    ipcRenderer.on('file-changed', callback);
    return () => ipcRenderer.removeListener('file-changed', callback);
  },
});
