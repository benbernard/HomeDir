const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('pickerIPC', {
  select: (sourceId) => ipcRenderer.send('picker-select', sourceId),
  cancel: () => ipcRenderer.send('picker-cancel'),
  showSources: (type) => ipcRenderer.send('picker-show-sources', type),
  useSystemPicker: () => ipcRenderer.send('picker-use-system'),
});
