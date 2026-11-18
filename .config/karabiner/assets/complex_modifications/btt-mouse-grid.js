// Add a new mouse model here using the IDs from EventViewer > Devices.
var mice = [
    { vendor_id: 0x04d9, product_id: 0xfc4d, is_keyboard: true } // USB Gaming Mouse
];

var keys = ['1','2','3','4','5','6','7','8','9','0','hyphen','equal_sign'];
var keypad = ['1','2','3','4','5','6','7','8','9','0','hyphen','plus'];
function mapKey(key, index) {
    // The first thumb key should be BTT Button 10; HID buttons start one higher.
    return {
        type: 'basic',
        conditions: [{ type: 'device_if', identifiers: mice }],
        from: { key_code: key, modifiers: { optional: ['any'] } },
        to: [{ pointing_button: 'button' + (11 + index) }]
    };
}
({
    description: 'Mouse thumb grid to BTT Buttons 10–21',
    manipulators: keys.map(mapKey).concat(keypad.map(function (key, i) {
        return mapKey('keypad_' + key, i);
    }))
});
