const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('meetyShare', {
  getScreenSources: () => ipcRenderer.invoke('get-screen-sources'),
  enableSystemPicker: () => ipcRenderer.invoke('enable-system-picker'),
  disableSystemPicker: () => ipcRenderer.invoke('disable-system-picker'),
});
