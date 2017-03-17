// Robert van Heumen 2011/2012
// Polling of controllers: Arduino, HID en MIDI
// Working with SC 3.6.6

// Data send to responders on IP 127.0.0.1 and port 57120
// Arduino responders: /ard/ana1, /ard/ana2, /ard/dig1, /ard/dig2
// HID extreme 3dpro responder: /hid/ex3d
// MIDI responders: /midi/noteOn, /midi/noteOff, /midi/control

// HID capture issues:
//	tijd tussen loops wordt heel groot bij retrigger
//	ook pedaal toevoegen

(
var version = "1.8GF";
var localAddr = NetAddr("127.0.0.1", 57120);
//var localAddr = NetAddrMon("127.0.0.1", 57120); // to monitor outgoing OSC, set ~oscOut = 1
var captureHIDenabled = 0; // set to 1 to switch on
var screenHeight = Window.screenBounds.height, screenWidth = Window.screenBounds.width;

var portName, ardSms, ardTask, ardLabel;
var ardAna1enable = 0, ardAna1, ardAna1Max = 950, ardAna1Min = 6; // calibration Arduino input 1
var ardAna2enable = 1, ardAna2, ardAna2Max = 800, ardAna2Min = 3, ardAna2prev = 0; // calibration Arduino input 2
var ardDig1enable = 1, ardDig1, ardDig1prev = 0;
var ardDig2enable = 1, ardDig2, ardDig2prev = 0;
var ardAna1avail, ardAna2avail, ardDig1avail, ardDig2avail;
var ex3dProArrayNbr, ex3dProVendor = 0, hidLabel, ex3dAvail;
var destTP1ArrayNbr, destTP1Loc = 0, destTP2ArrayNbr, destTP2Loc = 0, destTP1Avail, destTP2Avail;
var iac1ID = 0, iac1i, mulID = 0, lpkID = 0, midisportID = 0, nonResp, nofResp, cResp, mulAvail, midiLabel, iac1Avail, lpkAvail, midisportAvail;
var hidCookie = List.new(), hidValue = List.new(), hidTime = List.new(), captureHID = 0, startHIDseries = 0, fRunHID, tRunHID, sRunHID = 0;
var fontLabel = Font("Helvetica",12), fontButton = Font("Helvetica",12);

"GlobalVarsGF.scd".loadRelative();
// if(~oscSrc == "jx", {"/Users/robert/---data---/audio/junXion/HID2SC.j4xml/".openOS});

///////////////////////////////////////////// Arduino data acquisition //////////////////////////////////////

["Serial", SerialPort.devices].postln;
portName = SerialPort.devices.detect{|x| x.contains("tty.usb")};
if(portName.notNil, {
	("Connected to serial port" + portName ++ ".").postln;
	ardSms = ArduinoSMS(portName, 115200);
	ardSms.action = {
		| ... msg |
		// msg.postln;
		if(ardAna1enable == 1,
			{
				ardAna1 = (msg[0] - ardAna1Min ) / ardAna1Max;
				localAddr.sendMsg("/ard/ana", 1, ardAna1);
		});
		if(ardAna2enable == 1,
			{
				ardAna2 = min(1, max(0, (msg[1] - ardAna2Min )) / ardAna2Max);
				if(ardAna2 != ardAna2prev, {
					localAddr.sendMsg("/ard/ana", 2,  ardAna2);
					// ardAna2.postln;
					ardAna2prev = ardAna2;
				});
				//			ardAna2.postln;
		});
		if(ardDig1enable == 1,
			{
				ardDig1 = msg[2];
				if(ardDig1 != ardDig1prev, {
					localAddr.sendMsg("/ard/dig", 1, ardDig1);
					ardDig1prev = ardDig1;
				});
		});
		if(ardDig2enable == 1,
			{
				ardDig2 = msg[3];
				if(ardDig2 != ardDig2prev, {
					localAddr.sendMsg("/ard/dig", 2, ardDig2);
					ardDig2prev = ardDig2;
				});
		});
	};

	ardTask = Task({
		inf.do { ardSms.send($r);  0.05.wait; } // where $r is the Char r
	});
	ardTask.start;
	},
	{"No serial port found with name matching 'tty.usbmodem'.".postln}
);


///////////////////////////////////////////// HID data acquisition //////////////////////////////////////

// if (HIDDeviceService.buildDeviceList(nil,nil) != nil, {
// 	// get the array number of extreme3DPro and Destroyer Tiltpads
// 	i = 0;
// 	HIDDeviceService.devices.do({arg dev;
// 		["HID", i, dev.manufacturer, dev.product, dev.usage, dev.vendorID, dev.productID, dev.locID].postln;
// 		if(dev.product == "Logitech Extreme 3D",
// 			{
// 				ex3dProArrayNbr = i;
// 				ex3dProVendor = dev.vendorID;
// 				("Connected to Extreme 3D Pro device at slot " ++ ex3dProArrayNbr ++ ".").postln;
// 		});
// 		if(dev.product == "Destroyer Tiltpad",
// 			{
// 				if(destTP1Loc == 0,
// 					{ // first Tiltpad
// 						destTP1ArrayNbr = i;
// 						destTP1Loc = dev.locID;
// 						("Connected to Destroyer Tiltpad first device at slot " ++ destTP1ArrayNbr ++ ".").postln;
// 					},
// 					{ // second Tiltpad
// 						destTP2ArrayNbr = i;
// 						destTP2Loc = dev.locID;
// 						("Connected to Destroyer Tiltpad second device at slot " ++ destTP2ArrayNbr ++ ".").postln;
// 				});
// 		});
// 		i = i + 1;
// 	});
// 	// Destroyer Tiltpad first device
// 	if(destTP1Loc != 0,
// 		{
// 			HIDDeviceService.devices.at(destTP1ArrayNbr).queueDevice;
// 		},
// 		{
// 			"No Destroyer Tiltpad device found.".postln;
// 	});
// 	// Destroyer Tiltpad second device
// 	if(destTP2Loc != 0,
// 		{
// 			HIDDeviceService.devices.at(destTP2ArrayNbr).queueDevice;
// 		},
// 		{
// 			"No second Destroyer Tiltpad device found.".postln;
// 	});
// 	// Logitech Extreme 3D Pro
// 	if(ex3dProVendor != 0,
// 		{
// 			HIDDeviceService.devices.at(ex3dProArrayNbr).queueDevice;
// 		},
// 		{
// 			"No Extreme 3D Pro device found.".postln;
// 	});
// 	// Set action and run eventloop
// 	if((ex3dProVendor != 0) || (destTP1Loc != 0) || (destTP2Loc != 0), {
// 		HIDDeviceService.action_({arg vendorID, productID, locID, cookie, val;
// 			//			[vendorID, productID, locID, cookie, val].postln;
//
// 			if((vendorID != ex3dProVendor) && (locID == destTP1Loc),
// 			{localAddr.sendMsg("/hid/desttp1", cookie, val);});
// 			if((vendorID != ex3dProVendor) && (locID == destTP2Loc),
// 			{localAddr.sendMsg("/hid/desttp2", cookie, val);});
// 			if(vendorID == ex3dProVendor,
// 			{localAddr.sendMsg("/hid/ex3d", cookie, val);});
//
// 			// panic button
// 			if((cookie == 11) && (vendorID == ex3dProVendor) && (val == 0),
// 				{
// 					tRunHID.stop;
// 					localAddr.sendMsg("/panic");
// 			});
//
// 			// capture HID switch
// 			if(cookie == 18 && val == 1 && captureHIDenabled == 1, {
// 				captureHID = (captureHID + 1)%2;
// 				if(captureHID == 1, {
// 					"Start capture HID".postln;
// 					startHIDseries = SystemClock.seconds;
// 					hidCookie.clear;
// 					hidValue.clear;
// 					hidTime.clear;
// 					},
// 					{
// 						"Stop capture HID".postln;
// 						hidCookie.postln;
// 						hidValue.postln;
// 						hidTime.postln;
// 				});
// 			});
//
// 			// capture HID
// 			if(captureHID == 1 && cookie != 18,
// 				{
// 					hidCookie.add(cookie);
// 					hidValue.add(val);
// 					hidTime.add(SystemClock.seconds - startHIDseries);
// 			});
//
// 			// playback HID captured
// 			if(cookie == 18 && val == 5 && captureHIDenabled == 1, {
// 				"Playback captured HID".postln;
// 				sRunHID = (sRunHID + 1)%2;
// 				if(sRunHID == 1,
// 					{
// 						tRunHID = Task(fRunHID).play;
// 						// disable X-axis on joystick to prevent double triggering of zones
// 						localAddr.sendMsg("/disablex",1);
// 					},
// 					{
// 						tRunHID.stop;
// 						// stop all zone6 synths in LiveSampler
// 						localAddr.sendMsg("/panic",6);
// 						// enable X-axis on joystick
// 						localAddr.sendMsg("/disablex",0);
// 				});
// 			});
//
// 			//			mimic control by anne
// 			//			if(cookie == 16,
// 			//				{localAddr.sendMsg("/act", (val / 1023) * 1000);});
// 			//
// 			//			if(cookie == 4,
// 			//				{localAddr.sendMsg("/asw", val);});
//
// 		});
//
// 		HIDDeviceService.runEventLoop;
// 	});
// 	},
// 	{"No HID devices found.".postln}
// );


///////////////////////////////////////////// functions //////////////////////////////////////

fRunHID = {
	inf.do({
		hidCookie.size.do({arg i;
			if(i > 0, {(hidTime.at(i) - hidTime.at(i - 1)).wait;});
			localAddr.sendMsg("/hid/ex3d", hidCookie.asArray.at(i), hidValue.at(i));
		});
	});
};


///////////////////////////////////////////// MIDI acquisition //////////////////////////////////////

nonResp = NoteOnResponder({ |src,chan,note,vel|
	//	["NON", src,chan,note,vel].postln;
	localAddr.sendMsg("/midi/noteOn", chan, note, vel / 127,
		case {src == iac1ID}{"IAC1"}{src == mulID}{"MUL"}{src == lpkID}{"LPK"}{src == midisportID}{"MSP"});
	},
	nil, // source
	nil, // any channel
	nil, // any CC number
	nil // any value
);

nofResp = NoteOffResponder({ |src,chan,note,vel|
	//	["NOF", src,chan,note,vel].postln;
	localAddr.sendMsg("/midi/noteOff", chan, note, vel / 127,
		case {src == iac1ID}{"IAC1"}{src == mulID}{"MUL"}{src == lpkID}{"LPK"}{src == midisportID}{"MSP"});
	},
	nil, // source
	nil, // any channel
	nil, // any CC number
	nil // any value
);

cResp = CCResponder({ |src,chan,note,value|
	//	["CC", src,chan,note,value].postln;
	localAddr.sendMsg("/midi/control", chan, note, value / 127,
		case {src == iac1ID}{"IAC1"}{src == mulID}{"MUL"}{src == lpkID}{"LPK"}{src == midisportID}{"MSP"});
	},
	nil, // source
	nil, // any channel
	nil, // any CC number
	nil // any value
);

MIDIClient.sources.size.do({|i|
	//	MIDIClient.sources[i].device.postln;
	//	MIDIClient.sources[i].uid.postln;
	case
	{MIDIClient.sources[i].device == "UltraLite mk3 Hybrid" && MIDIClient.sources[i].name == "MIDI Port"}
	{
		mulID = MIDIClient.sources[i].uid;
		if((~midiOutInit == 1) && (~midiOutDevice == "MUL"), {
			~midiOut = MIDIOut(i);
			~midiOut.latency_(0.01);
			"MIDI out to MUL".postln;
		});
	}
	{MIDIClient.sources[i].device == "LPK25" && MIDIClient.sources[i].name == "LPK25"}
	{lpkID = MIDIClient.sources[i].uid}
	{MIDIClient.sources[i].device == "MIDISPORT 2x2" && MIDIClient.sources[i].name == "Port A"}
	{
		midisportID = MIDIClient.sources[i].uid;
		if((~midiOutInit == 1) && (~midiOutDevice == "MSP"), {
			~midiOut = MIDIOut(i);
			~midiOut.latency_(0.01);
			"MIDI out to MSP".postln;
		});
	}
	{MIDIClient.sources[i].device == "IAC Driver" && MIDIClient.sources[i].name == "IAC Bus 1"}
	{
		iac1ID = MIDIClient.sources[i].uid;
		iac1i = i;
		if((~midiOutInit == 1) && (~midiOutDevice == "IAC1"), {
			~midiOut = MIDIOut(i);
			~midiOut.latency_(0.01);
			"MIDI out to IAC1".postln;
		});
	}
	;
});

// if MIDI out should be initialized but midiOut is still nil, use IAC1
if((~midiOutInit == 1) && ~midiOut.isNil, {
	~midiOut = MIDIOut(iac1i);
	~midiOut.latency_(0.01);
	("MIDI out to IAC1 (since" + ~midiOutDevice + "is not available)").postln;
	~midiOutDevice = "IAC1";
});


///////////////////////////////////////////// GUI //////////////////////////////////////

~wControllers = Window("Controllers" + version, Rect(650, (screenHeight - 160), 280, 100),false);
//~wControllers.alpha_(0.9);
~wControllersAvail = 1;

ardLabel = StaticText(~wControllers, Rect(20, 12, 50, 16))
.font_(fontLabel)
.background_(Color.white.alpha_(0.7))
.string_(" Arduino ");

ardAna1avail = SmoothButton(~wControllers, Rect(85,10,40,20))
.border_(1)
.radius_(3)
.canFocus_(false)
.font_(fontButton)
.background_(Color.white)
.states_([["Ana1"]]);

ardAna2avail = SmoothButton(~wControllers, Rect(130,10,40,20))
.border_(1)
.radius_(3)
.canFocus_(false)
.font_(fontButton)
.background_(Color.white)
.states_([["Ana2"]]);

ardDig1avail = SmoothButton(~wControllers, Rect(175,10,40,20))
.border_(1)
.radius_(3)
.canFocus_(false)
.font_(fontButton)
.background_(Color.white)
.states_([["Dig1"]]);

ardDig2avail = SmoothButton(~wControllers, Rect(220,10,40,20))
.border_(1)
.radius_(3)
.canFocus_(false)
.font_(fontButton)
.background_(Color.white)
.states_([["Dig2"]]);

hidLabel = StaticText(~wControllers, Rect(20, 42, 50, 16))
.font_(fontLabel)
.background_(Color.white.alpha_(0.7))
.string_(" HID ");

ex3dAvail = SmoothButton(~wControllers, Rect(85,40,40,20))
.border_(1)
.radius_(3)
.canFocus_(false)
.font_(fontButton)
.background_(Color.white)
.states_([["Ex3d"]]);

destTP1Avail = SmoothButton(~wControllers, Rect(130,40,40,20))
.border_(1)
.radius_(3)
.canFocus_(false)
.font_(fontButton)
.background_(Color.white)
.states_([["Tilt1"]]);

destTP2Avail = SmoothButton(~wControllers, Rect(175,40,40,20))
.border_(1)
.radius_(3)
.canFocus_(false)
.font_(fontButton)
.background_(Color.white)
.states_([["Tilt2"]]);

midiLabel = StaticText(~wControllers, Rect(20, 72, 50, 16))
.font_(fontLabel)
.background_(Color.white.alpha_(0.7))
.string_(" MIDI ");

mulAvail = SmoothButton(~wControllers, Rect(85,70,40,20))
.border_(1)
.radius_(3)
.canFocus_(false)
.font_(fontButton)
.background_(Color.white)
.states_([["MUL"]]);

iac1Avail = SmoothButton(~wControllers, Rect(130,70,40,20))
.border_(1)
.radius_(3)
.canFocus_(false)
.font_(fontButton)
.background_(Color.white)
.states_([["IAC1"]]);

lpkAvail = SmoothButton(~wControllers, Rect(175,70,40,20))
.border_(1)
.radius_(3)
.canFocus_(false)
.font_(fontButton)
.background_(Color.white)
.states_([["LPK"]]);

midisportAvail = SmoothButton(~wControllers, Rect(220,70,40,20))
.border_(1)
.radius_(3)
.canFocus_(false)
.font_(fontButton)
.background_(Color.white)
.states_([["MSP"]]);

w = Window("dummy").front; w.close;
~wControllers.front;
if(~alwaysOnTop == 1, {~wControllers.alwaysOnTop_(true)});
if(~wInOutAvail == 1, {localAddr.sendMsg("/imageRefresh")}); // request image refresh

// GUI
if(portName.notNil, {
	if(ardAna1enable == 1, {ardAna1avail.background_(~colorOn);});
	if(ardAna2enable == 1, {ardAna2avail.background_(~colorOn);});
	if(ardDig1enable == 1, {ardDig1avail.background_(~colorOn);});
	if(ardDig2enable == 1, {ardDig2avail.background_(~colorOn);});
});
if(ex3dProVendor != 0, {ex3dAvail.background_(~colorOn);});
if(destTP1Loc != 0, {destTP1Avail.background_(~colorOn);});
if(destTP2Loc != 0, {destTP2Avail.background_(~colorOn);});
if(mulID != 0, {mulAvail.background_(~colorOn);});
if(iac1ID != 0, {iac1Avail.background_(~colorOn);});
if(lpkID != 0, {lpkAvail.background_(~colorOn);});
if(midisportID != 0, {midisportAvail.background_(~colorOn);});

// collect garbage
~wControllers.onClose_({
	ardTask.stop;
	localAddr.disconnect;
	if((ardSms != nil), {ardSms.close;});
	// HIDDeviceService.stopEventLoop;
	cResp.remove;
	nonResp.remove;
	nofResp.remove;
	~wControllersAvail = nil;
});

)
