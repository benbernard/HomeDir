// The module 'vscode' contains the VS Code extensibility API
// Import the module and reference it with the alias vscode in your code below
const vscode = require('vscode');

// This method is called when your extension is activated
// Your extension is activated the very first time the command is executed

/**
 * @param {vscode.ExtensionContext} context
 */
function activate(context) {

	// Use the console to output diagnostic information (console.log) and errors (console.error)
	// This line of code will only be executed once when your extension is activated
	console.log('BenX Activated');

	// Create a new file in the current files directory
	let createFile = vscode.commands.registerCommand('benx.createFile', async function () {
		let editor = vscode.window.activeTextEditor;

		if (!editor) {
			// show message about not being in a file
			vscode.window.showInformationMessage('Sorry, no open text editor');
			return;
		}

		// Get the current file path
		let currentFilePath = vscode.window.activeTextEditor.document.fileName;
		// Get the current file directory
		let currentFileDirectory = currentFilePath.substring(0, currentFilePath.lastIndexOf('/'));

		// create cancellation token
		const cancellationToken = new vscode.CancellationTokenSource().token;
		// Get the new file name
		// With prompt
		let newFileName = await vscode.window.showInputBox({
			prompt: 'Enter the new file name',
			value: currentFileDirectory + '/',
			validateInput: (value) => {
				if (value.length === 0) {
					return 'Please enter a file name';
				}

				// Check if input was changed
				if (value === currentFileDirectory + '/') {
					return 'Please enter a new file name';
				}

				return null;
			},
			valueSelection: [currentFileDirectory.length + 1, currentFileDirectory.length + 1],
		}, cancellationToken);

		// If the user cancels, return
		if (cancellationToken.isCancellationRequested || !newFileName) {
			return;
		}

		let fullNewFilePath = newFileName;
		// If the path is not rooted, add the current file directory
		if (!newFileName.startsWith('/')) {
			fullNewFilePath = currentFileDirectory + '/' + newFileName;
		}

		// Get the current file extension
		let currentFileExtension = currentFilePath.substring(currentFilePath.lastIndexOf('.'));
		// if the file has no extension, add the current extension
		if (!newFileName.includes('.')) {
			fullNewFilePath += currentFileExtension;
		}

		// Do nothing if file already exists
		try {
			if (await vscode.workspace.fs.stat(vscode.Uri.file(fullNewFilePath))) {
				vscode.window.showInformationMessage(`File ${fullNewFilePath} already exists`);
				return;
			}
		} catch (error) {
			// Check if the error is that the file does not exist
			// If it is, continue
			if (error.code !== 'FileNotFound') {
				throw error
			}
		}

		// Create the new file
		await vscode.workspace.fs.writeFile(vscode.Uri.file(fullNewFilePath), new Uint8Array());
		// Open the new file
		let doc = await vscode.workspace.openTextDocument(fullNewFilePath)
		await vscode.window.showTextDocument(doc);
	});
	context.subscriptions.push(createFile);
}

// This method is called when your extension is deactivated
function deactivate() {}

module.exports = {
	activate,
	deactivate
}