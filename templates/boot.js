const path = require('path');
const { app } = require('electron');

Object.defineProperty(app, 'isPackaged', { value: true, configurable: true });
Object.defineProperty(process, 'resourcesPath', {
  value: path.join(__dirname, 'resources'),
  configurable: true,
  writable: false,
  enumerable: true,
});

require('./resources/app/main.js');
