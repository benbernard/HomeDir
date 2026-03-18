const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('meetyShare', {
  // Show the custom picker and return the user's choice:
  // - A source ID string (e.g., 'screen:0:0') for Entire Screen
  // - '__system_picker__' for Application Window
  // - null for cancel
  showPicker: () => ipcRenderer.invoke('meety-show-picker'),
});
