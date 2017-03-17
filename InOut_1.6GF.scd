// InOut: Audio Output Central by Robert van Heumen 2013.
// Tested with SC 3.6.6.

// There are three audio busses you can send Synths to:
// ~aBus.outA (Synth outBusA):
//	sending to efxBus pre-fade for internal efx
//	volume control by Faderfox knob
//	sending to efxBus post-fade for internal efx
// 	sending to outBusMain for last output stage
// ~aBus.outB (Synth outBusB):
//	sending to efxBus pre-fade for internal efx
//	volume control by footpedal via Arduino
//	sending to efxBus post-fade for internal efx
// 	sending to outBusMain for last output stage
// ~aBus.outBL (Synth outBusBL):
//	sending to efxBus pre-fade for internal efx
//	volume control by footpedal via Arduino
//	adding limiter
//	sending to efxBus post-fade for internal efx
// 	sending to outBusMain for last output stage
// ~aBus.outMain (Synth outBusMain):
//	recording in ~processBuf
// 	sending out for resampling
//	check bad values and possibly add subfilter
//	send mono limited to output for analog efx
//	possibly add limiter
//	send to output for monitor with realtime attenuation
//	send to output for mains with realtime attenuation

// Configuration switches on LX
//	RED1 switches between original (RED1=off) and alternative (RED1=on) audio inputs as specified in GlobalVars.rtf
//	RED4 switches between external (RED4=off) and internal (RED4=on, channel 11/12) audio inputs

(
s.waitForBoot({

	///////////////////////////////////////////// Local vars //////////////////////////////////////

	var sRate = s.sampleRate;
	var cfg = (
		version: "1.6GF",
		controllersFile: "Controllers_1.8GF.scd",
		processLen: sRate * 30,
		localAddr: NetAddr("127.0.0.1", 57120),
		// docDir: Document.dir,
		// libDir: "../Data/",
		startMeter: 1, // start meter window
		startCueMix: 0, // start Motu CueMix FX
		startActMon: 0, // start Activity Monitor
		startMOTUSetup: 0, // start MOTU Audio Setup to check return assign channel
		midiSrc: "MUL", // filtering allowed midi sources; comma-separated list f.e.: MUL = Motu Ultralite, IAC1, IAC2, IAC3, LPK
		background: "pen",
		dummy: 0
	);
	var respArdAna, respCTR, respPanic, respNON, respNOF;
	var ardAna1Bus, midiLV2KnobMasterVol, fInitOutput, fSetImage, fProjectInfo, respRefreshImage;
	var specOutAmp = Env.xyc([[0.0, 0.0, \lin], [0.001, 0.001,\exp],[0.2, 0.2, \lin],[1, 1.0]]);
	var screenHeight = Window.screenBounds.height, screenWidth = Window.screenBounds.width;
	var mainOutChan, mainOutLabel, monOutLabel, monOutChan, inputLabel, inputChan;
	var outMonitorAttLabel, outMonitorAttVal, outMainAttLabel, outMainAttVal;
	var oscOn = 0;
	//var imageFileList = ["flower2","flower4","flower5","flower7","flower8","flower9","flower11"];
	var imageFileList = ["sound"];
	var imageFileDone = Array.new(imageFileList.size);
	var fontLabel = Font("Helvetica",12), fontButton = Font("Helvetica",12);

	~aBus = nil; // refresh global vars
	"GlobalVarsGF.scd".loadRelative();
	~processBuf = Buffer.alloc(s, cfg.processLen, 2);

	///////////////////////////////////////////// Output Synths //////////////////////////////////////

	SynthDef(\outBusA, {
		arg volBus, gate;
		var sig;
		sig = In.ar(~aBus.outA,2); 			// input from outA bus
		Out.ar(~aBus.outEfxPre, sig);		// output to efx bus pre-fade
		sig = In.kr(volBus,1) * sig * EnvGen.kr(Env.adsr(0,0,1,0),gate); // apply fade and envelope
		Out.ar(~aBus.outEfxPost, sig);	// output to efx bus post-fade
		Out.ar(~aBus.outMain, sig);		// output to main bus
	}).add;

	SynthDef(\outBusB, {
			arg volBus, gate;
			var sig;
			sig = In.ar(~aBus.outB,2);			// input from outB bus
			Out.ar(~aBus.outEfxPre, sig);		// output to efx bus pre-fade
			sig = In.kr(volBus,1) * sig * EnvGen.kr(Env.adsr(0,0,1,0),gate);	// apply fade and envelope
			Out.ar(~aBus.outEfxPost, sig);	// output to efx bus post-fade
			Out.ar(~aBus.outMain, sig);		// output to main bus
	}).add;

	SynthDef(\outBusBL, { // like outBusB but with limiter
			arg volBus, gate;
			var sig;
			sig = In.ar(~aBus.outBL,2);					// input from outBL bus
			Out.ar(~aBus.outEfxPre, sig);				// output to efx bus pre-fade
			sig = In.kr(volBus,1) * sig * EnvGen.kr(Env.adsr(0,0,1,0),gate);	// apply fade and envelope
			sig = Limiter.ar(sig, 0.90).clip2(0.95);  // limiter
			Out.ar(~aBus.outEfxPost, sig);			// output to efx bus post-fade
			Out.ar(~aBus.outMain, sig);				// output to main bus
	}).add;

	SynthDef(\outBusMain,{
			arg gate, monAtt, mainAtt, resampAtt; var sig, sigMon;

			sig = In.ar(~aBus.outMain,2) * EnvGen.kr(Env.adsr(0,0,1,0),gate);

			// fill circular process buffer
			RecordBuf.ar(sig, ~processBuf, loop: 1);

			// output for resampling (stereo) - has to be done in the main output stage to be able to resample efx too
			if(~aBus.outResampling == 1, {
				Out.ar(~aBus.outResamplingChan, resampAtt * sig);
			});

			// tidy up the signal, getting ready to send out
			sig = Select.ar(CheckBadValues.ar(sig, 0, 0), [sig, DC.ar(0), DC.ar(0), sig]);  // don't let bad math hit the speakers
			if(~aBus.outMainSubFilter == 1, {sig = HPF.ar(sig, 50); "InOut: subfilter enabled.".postln;}); // reduce subsonics

			// analog efx output (mono) with limiter
			if(~aBus.outAnalogEfx == 1, {
				Out.ar(~aBus.outAnalogEfxChan, ~aBus.outAnalogEfxAtt * Mix.new(Limiter.ar(sig, 0.9).clip2(0.95)));
			});

			// master limiter
			if(~aBus.outMainLimiter == 1, {sig = Limiter.ar(sig, 0.95).clip2(0.98); "InOut: limiter enabled.".postln;});

			// monitor output
			if(~aBus.outMonitor == 1, {
				if(~aBus.outMonitorStereo == 0, {sigMon = Mix.new(sig)}, {sigMon = sig}); // if mono mixdown to one channel
				Out.ar(~aBus.outMonitorChan, monAtt * sigMon);
			});

			// main output
			if(~aBus.outMainStereo == 0, {sig = Mix.new(sig);});	// if mono mixdown to one channel
			Out.ar(~aBus.outMainChan, mainAtt * sig);
	}).add;

	s.sync; // to enable SynthDefs to be send to the server

	///////////////////////////////////////////// Init //////////////////////////////////////

	ardAna1Bus = Bus.control(s,1);
	ardAna1Bus.set(specOutAmp.at(1));
	midiLV2KnobMasterVol = Bus.control(s,1);
	midiLV2KnobMasterVol.set(specOutAmp.at(1));

	///////////////////////////////////////////// Functions //////////////////////////////////////

	fInitOutput = {
		arg mode, onClose = 0;
		if(mode == 0,
			{ // stop sound
				~aBus.synthGroup.free;
				~aBus.mainGroup.free;
				~aBus.efxGroup.free;
				~aBus.outputGroup.free;
				if(onClose==0, {mainOutChan.background_(Color.white)});
				if(~aBus.outMonitor == 1, {monOutChan.background_(Color.white)});
				"InOut: output stopped.".postln;
			},
			{ // init sound
				~aBus.synthGroup = Group.new();
				~aBus.outputGroup = Group.new(~aBus.synthGroup, \addAfter);
				~aBus.efxGroup = Group.new(~aBus.outputGroup, \addAfter);
				~aBus.mainGroup = Group.new(~aBus.efxGroup, \addAfter);
				~aBus.outAsynth = Synth(\outBusA, [\volBus, midiLV2KnobMasterVol.index,
					\gate,1], target: ~aBus.outputGroup);
				~aBus.outBsynth = Synth(\outBusB, [\volBus, ardAna1Bus.index,
					\gate,1], target: ~aBus.outputGroup);
				~aBus.outBLsynth = Synth(\outBusBL, [\volBus, ardAna1Bus.index,
					\gate,1], target: ~aBus.outputGroup);
				~aBus.outMainsynth = Synth(\outBusMain, [\gate,1,
					\monAtt,~aBus.outMonitorAtt.asFloat,\mainAtt,~aBus.outMainAtt.asFloat,\resampAtt,~aBus.outResamplingAtt.asFloat],
					target: ~aBus.mainGroup);
				mainOutChan.background_(~colorOn);
				if(~aBus.outMonitor == 1, {monOutChan.background_(~colorOn)});
				outMainAttVal.value = ~aBus.outMainAtt;
				if(~aBus.outMonitor == 1, {outMonitorAttVal.value = ~aBus.outMonitorAtt; });
				"InOut: output initialized.".postln;
		});
	};

	fSetImage = {
		var alpha = 0.9, colorBg = Color.white(0.9);
		var imageObj, imageFile, imageFound = 0, imageFileIndex;
		if(cfg.background == "", {cfg.background = ["pen","image"].choose});
		if(cfg.background == "pen", { // pen drawing
			~wInOut
			.background_(colorBg)
			.alpha_(alpha)
			.drawFunc = {
				Pen.translate(50, 20);
				10.do{
					// set the Color
					Pen.color = Color.green(rrand(0.0, 0.5), rrand(0.0, 0.5));
					Pen.addArc((100.rand)@(100.rand), rrand(10, 100), 2pi.rand, pi);
					Pen.perform(\stroke);
				}
			};
			~wInOut.refresh;
			if(~wLiveSamplerAvail.notNil, {
				~wLiveSampler
				.background_(colorBg)
				.alpha_(alpha)
				.drawFunc = {
					Pen.translate(50, 20);
					10.do{
						// set the Color
						Pen.color = Color.green(rrand(0.0, 0.2), rrand(0.0, 0.5));
						Pen.addArc((100.rand)@(100.rand), rrand(10, 100), 2pi.rand, pi);
						Pen.perform(\stroke);
					}
				};
				~wLiveSampler.refresh;
			});
			if(~wSynthKeysAvail.notNil, {
				~wSynthKeys
				.background_(colorBg)
				.alpha_(alpha)
				.drawFunc = {
					Pen.translate(50, 20);
					10.do{
						// set the Color
						Pen.width = 5;
						Pen.color = Color.green(rrand(0.0, 0.2), rrand(0.0, 0.1));
						Pen.addArc((100.rand)@(100.rand), rrand(10, 100), 2pi.rand, pi);
						Pen.perform(\stroke);
					}
				};
				~wSynthKeys.refresh;
			});
			if(~wControllersAvail.notNil, {
				w = ~wControllers
				.background_(colorBg)
				.alpha_(alpha)
				.drawFunc = {
					Pen.translate(50, 20);
					10.do{
						// set the Color
						Pen.color = Color.green(rrand(0.0, 0.5), rrand(0.0, 0.5));
						Pen.lineDash = FloatArray[1,3];
						Pen.width = 5;
						Pen.addArc((100.rand)@(100.rand), rrand(10, 100), 2pi.rand, pi);
						Pen.perform(\stroke);
					}
				};
				~wControllers.refresh;
			});
			},
			{ // display images
				// while(
				// 	{imageFound == 0},
				// 	{
				// 		imageFileIndex = imageFileList.size.rand;
				// 		if(imageFileDone.includes(imageFileIndex), {},
				// 			{
				// 				imageFileDone.add(imageFileIndex);
				// 				imageFound = 1;
				// 				if(imageFileDone.size == imageFileList.size, {imageFileDone = Array.new(imageFileList.size)});
				// 		});
				// });
				// imageFile = imageFileList[imageFileIndex];
				//
				// imageObj = Image.new(cfg.docDir ++ "/" ++ cfg.libDir ++ "Images/" ++ imageFile ++ "-1.png");
				// if(~wLiveSamplerAvail.notNil, {
				// 	~wLiveSampler.view.backgroundImage_(imageObj);
				// 	~wLiveSampler.background_(colorBg);
				// });
				// imageObj = Image.new(cfg.docDir ++ "/" ++ cfg.libDir ++ "Images/" ++ imageFile ++ "-2.png");
				// if(~wSynthKeysAvail.notNil, {
				// 	~wSynthKeys.view.backgroundImage_(imageObj);
				// 	~wSynthKeys.background_(colorBg);
				// });
				// imageObj = Image.new(cfg.docDir ++ "/" ++ cfg.libDir ++ "Images/" ++ imageFile ++ "-3.png");
				// if(~wControllersAvail.notNil, {
				// 	~wControllers.view.backgroundImage_(imageObj);
				// 	~wControllers.background_(colorBg);
				// });
				// imageObj = Image.new(cfg.docDir ++ "/" ++ cfg.libDir ++ "Images/" ++ imageFile ++ "-4.png");
				// ~wInOut.view.backgroundImage_(imageObj);
				// ~wInOut.background_(colorBg);
		});
	};

	fProjectInfo = {
		("\nProject "++~project++"...").postln;
		("\nRED1: Switch inputs 1 & 2 between" +  ~aBus.inChan1 + "&" + ~aBus.inChan2 +
			"to" + ~aBus.inChan1alt + "&" + ~aBus.inChan2alt).postln;
		"RED2: Switch efx bank from deciMate & deLay to multiTapFreeze & ampPitchFol".postln;
		"RED3: Switch efx source from sample playback to input channels".postln;
		("RED4: Switch input channels between"
			+~aBus.inChan1++" & "++~aBus.inChan2+"and"+~aBus.inChan1int++" & "++~aBus.inChan2int).postln;

		"\nInOut keyboard shortcuts:".postln;
		"	Esc stops sound output".postln;
		"	i changes background image and posts project info".postln;
		"	N posts Node info".postln;
		"	M starts s.meter".postln;
		"	O toggles OSC monitor ON/OFF".postln;
		"	pageUp/Down increments/decrements MainAtt (use shift to step 0.01)".postln;
		"	apple-pageUp/Down increments/decrements MonitorAtt (use shift to step 0.01)".postln;

		"\nLiveSampler keyboard shortcuts:".postln;
		"	Esc stops sound output".postln;
		"	L clears buffer".postln;
		// "	P plots buffer".postln;
		"	A amplifies current zone".postln;
		"	S saves buffer to disk".postln;
		"	T loads ~testSampleList".postln;
		"	R refreshes bufferView".postln;

		"\nSynthKeys keyboard shortcuts:".postln;
		"	Esc stops sound output".postln;
		"	S saves buffer to disk\n".postln;
		// "	Pageup/down selects next/previous synth for channel 1\n".postln;
	};

	///////////////////////////////////////////// Arduino //////////////////////////////////////
	// responder for analog sensors

	respArdAna = OSCresponderNode(nil, "/ard/ana",{ arg time, responder, msg;
		//	("SynthKeys OSC RCV ArdAna: " ++ msg).postln;
		case
		{msg[1] == 1} {}
		{msg[1] == 2} {ardAna1Bus.set(specOutAmp.at(msg[2]));}
		;
	}).add;

	///////////////////////////////////////////// MIDI //////////////////////////////////////
	respCTR = OSCresponderNode(nil, "/midi/control", { arg time, responder, msg;
		var chan, num, value, src;
		chan = msg[1];
		num = msg[2];
		value = msg[3];
		src = msg[4].asString;
		//	[chan,num,value, src].postln;

		// only process midi if coming from the right source
		if(cfg.midiSrc.find(src).notNil, {
			// main volume control
			if((chan==11 && num==17), {
				midiLV2KnobMasterVol.set(specOutAmp.at(value));
			});
		}); // only process midi if coming from the right source
	}).add;

	respNON = OSCresponderNode(nil, "/midi/noteOn", { arg time, responder, msg;
		var chan, note, value, src;
		chan = msg[1];
		note = msg[2];
		value = msg[3];
		src = msg[4].asString;
		//	[chan,note,value, src].postln;

		// only process midi if coming from the right source
		if(cfg.midiSrc.find(src).notNil, {
			// input channels switching
			if(chan == 0, {
				case
				{(note == 0) && (~aBus.inAlt == 0)} // switching input 1 & 2 to alternative
				{
					("InOut: Switch inputs 1 & 2 from" + ~aBus.inChan1 + "&" + ~aBus.inChan2 +
						"to" + ~aBus.inChan1alt + "&" + ~aBus.inChan2alt).postln;
					~aBus.inChan1 = ~aBus.inChan1alt;
					~aBus.inChan2 = ~aBus.inChan2alt;
					~aBus.inAlt = 1;
					inputChan.states_([[~aBus.inChan1.asString ++ "," ++ ~aBus.inChan2.asString]]);
				}
				{(note == 3) && (~aBus.inInt == 0)} // switching inputs 1 & 2 to internal
				{
					("InOut: Switch inputs 1 & 2 from" + ~aBus.inChan1 + "&" + ~aBus.inChan2 +
						"to" + ~aBus.inChan1int + "&" + ~aBus.inChan2int).postln;
					~aBus.inChan1 = ~aBus.inChan1int;
					~aBus.inChan2 = ~aBus.inChan2int;
					~aBus.inInt = 1;
					inputChan.states_([[~aBus.inChan1.asString ++ "," ++ ~aBus.inChan2.asString]]);
				};
			});
		}); // only process midi if coming from the right source
	}).add;

	respNOF = OSCresponderNode(nil, "/midi/noteOff", { arg time, responder, msg;
		var chan, note, value, src;
		chan = msg[1];
		note = msg[2];
		value = msg[3];
		src = msg[4].asString;
		//	[chan,note,value, src].postln;

		// only process midi if coming from the right source
		if(cfg.midiSrc.find(src).notNil, {
			// input channels switching
			if(chan==0, {
				case
				{(note == 0) && (~aBus.inAlt == 1)} // switching input 1 & 2 back to original
				{
					("InOut: Switch inputs 1 & 2 from" + ~aBus.inChan1 + "&" + ~aBus.inChan2 +
						"to" + ~aBus.inChan1org + "&" + ~aBus.inChan2org).postln;
					~aBus.inChan1 = ~aBus.inChan1org;
					~aBus.inChan2 = ~aBus.inChan2org;
					~aBus.inAlt = 0;
					inputChan.states_([[~aBus.inChan1.asString ++ "," ++ ~aBus.inChan2.asString]]);
				}
				{(note == 3) && (~aBus.inInt == 1)} // switching inputs 1&2 to back to what they were
				{
					("InOut: Switch inputs 1 & 2 from" + ~aBus.inChan1 + "&" + ~aBus.inChan2 + "to" +
						if(~aBus.inAlt == 0, {~aBus.inChan1org}, {~aBus.inChan1alt})  + "&" +
						if(~aBus.inAlt == 0, {~aBus.inChan2org}, {~aBus.inChan2alt})).postln;
					~aBus.inChan1 = if(~aBus.inAlt == 0, {~aBus.inChan1org}, {~aBus.inChan1alt});
					~aBus.inChan2 = if(~aBus.inAlt == 0, {~aBus.inChan2org}, {~aBus.inChan2alt});
					~aBus.inInt = 0;
					inputChan.states_([[~aBus.inChan1.asString ++ "," ++ ~aBus.inChan2.asString]]);
				};
			});
		}); // only process midi if coming from the right source
	}).add;

	///////////////////////////////////////////// OSC responders //////////////////////////////////////
	// responder to stop everything
	respPanic = OSCresponderNode(nil, "/panic", {
		arg time, responder, message;
		"Panic InOut".postln;
		{fInitOutput.value(0)}.defer();
		{fInitOutput.value(1)}.defer(0.1);
	}).add;

	// responder to refresh image
	respRefreshImage = OSCresponderNode(nil, "/imageRefresh", {
		arg time, responder, message;
		{fSetImage.value()}.defer();
	}).add;

	///////////////////////////////////////////// GUI //////////////////////////////////////

	~wInOut = Window("InOut" + cfg.version + "  |  " + ~project, Rect(940, (screenHeight - 160), 265, 100), false);
	~wInOutAvail = 1;

	inputLabel = StaticText(~wInOut, Rect(40, 12, 50, 16))
	.font_(fontLabel)
	.background_(Color.white.alpha_(0.7))
	.string_(" Input ");

	inputChan = SmoothButton(~wInOut, Rect(105,10,45,20))
	.border_(1)
	.radius_(3)
	.canFocus_(false)
	.font_(fontButton)
	.background_(Color.white)
	.states_([[~aBus.inChan1.asString ++ "," ++ ~aBus.inChan2.asString]]);

	mainOutLabel = StaticText(~wInOut, Rect(40, 42, 50, 16))
	.font_(fontLabel)
	.background_(Color.white.alpha_(0.7))
	.string_(" Output ");

	mainOutChan = SmoothButton(~wInOut, Rect(105,40,45,20))
	.border_(1)
	.radius_(3)
	.canFocus_(false)
	.font_(fontButton)
	.states_([[
		if(~aBus.outMainStereo == 1,
			{~aBus.outMainChan.asString ++ "," ++ (~aBus.outMainChan+1).asString},
			{~aBus.outMainChan.asString})
	]]);

	outMainAttLabel = StaticText(~wInOut, Rect(164, 42, 15, 16))
	.background_(Color.white.alpha_(0.7))
	.font_(fontLabel)
	.align_(\center)
	.string_(" x ");

	outMainAttVal = SmoothNumberBox(~wInOut, Rect(185, 40, 35, 20))
	.border_(1)
	.radius_(3)
	.background_(Color.white)
	.font_(fontButton)
	.value_(~aBus.outMainAtt)
	.clipHi_(3.00)
	.clipLo_(0.00)
	.canFocus_(false)
	.scroll_step_(0.1)
	.step_(0.01)
	.action_({
		~aBus.outMainAtt = outMainAttVal.value;
		("Main Att:" + ~aBus.outMainAtt).postln;
		~aBus.outMainsynth.set(\mainAtt,~aBus.outMainAtt);
	});

	if(~aBus.outMonitor == 1, {
		monOutLabel = StaticText(~wInOut, Rect(40, 72, 50, 16))
		.font_(fontLabel)
		.background_(Color.white.alpha_(0.7))
		.string_(" Monitor ");

		monOutChan = SmoothButton(~wInOut, Rect(105,70,45,20))
		.border_(1)
		.radius_(3)
		.canFocus_(false)
		.font_(fontButton)
		.states_([[
			if(~aBus.outMonitorStereo == 1,
				{~aBus.outMonitorChan.asString ++ "," ++ (~aBus.outMonitorChan+1).asString},
				{~aBus.outMonitorChan.asString});
		]]);

		outMonitorAttLabel = StaticText(~wInOut, Rect(164, 72, 15, 16))
		.background_(Color.white.alpha_(0.7))
		.font_(fontLabel)
		.align_(\center)
		.string_(" x ");

		outMonitorAttVal = SmoothNumberBox(~wInOut, Rect(185, 70, 35, 20))
		.border_(1)
		.radius_(3)
		.background_(Color.white)
		.font_(fontButton)
		.value_(~aBus.outMonitorAtt)
		.clipHi_(3.00)
		.clipLo_(0.00)
		.canFocus_(false)
		.scroll_step_(0.1)
		.step_(0.01)
		.action_({
			~aBus.outMonitorAtt = outMonitorAttVal.value;
			("Monitor Att:" + ~aBus.outMonitorAtt).postln;
			~aBus.outMainsynth.set(\monAtt,~aBus.outMonitorAtt);
		});
	});

	~wInOut.view.keyDownAction_({
		arg view, char, modifiers, unicode, keycode;
		// [modifiers,keycode].postln;
		// Esc stops sound output
		if((keycode == 53), {cfg.localAddr.sendMsg("/panic");});
		// i changes background image and posts project info
		if((keycode ==34), {fSetImage.value(); fProjectInfo.value()});
		// N posts Node info
		if((keycode ==45), {s.queryAllNodes();});
		// M starts s.meter
		if((keycode ==46) && (~wMeterAvail.isNil), {s.meter;});
		// O starts OSC monitor
		if(keycode ==31, {
			if(oscOn == 0,
				{thisProcess.oscInMonitor(true, addr:1, excl: ['/hid/ex3d']); "OSC monitor is ON.".postln;},
				{thisProcess.oscInMonitor(false); "OSC monitor is OFF.".postln;});
			oscOn = (oscOn+1)%2;
		});
		// arrow up/down increment/decrement MainAtt of MonitorAtt (with apple modifier)
		if((keycode == 126) && (modifiers == 2097152), {outMainAttVal.increment(10)});
		if((keycode == 125) && (modifiers == 2097152), {outMainAttVal.decrement(10)});
		if((keycode == 126) && (modifiers == 2228224), {outMainAttVal.increment(1)});
		if((keycode == 125) && (modifiers == 2228224), {outMainAttVal.decrement(1)});
		if(~aBus.outMonitor == 1, {
			if((keycode == 126) && (modifiers == 3145728), {outMonitorAttVal.increment(10)});
			if((keycode == 125) && (modifiers == 3145728), {outMonitorAttVal.decrement(10)});
			if((keycode == 126) && (modifiers == 3276800), {outMonitorAttVal.increment(1)});
			if((keycode == 125) && (modifiers == 3276800), {outMonitorAttVal.decrement(1)});
		});
	});

	w = Window("dummy").front; w.close;
	~wInOut.front;
	if(~alwaysOnTop == 1, {~wInOut.alwaysOnTop_(true)});

	// initialize output
	fInitOutput.value(1);

	// image
	fSetImage.value();

	// postln project information
	fProjectInfo.value();

	// collect garbage
	~wInOut.onClose_({
		fInitOutput.value(0, onClose:1);
		respArdAna.remove;
		respCTR.remove;
		respNON.remove;
		respNOF.remove;
		respPanic.remove;
		// respRefreshImage.remove;
		~processBuf.free;
		if(~wControllersAvail.notNil, {~wControllers.close});
		if(~wLiveSamplerAvail.notNil, {~wLiveSampler.close});
		if(~wSynthKeysAvail.notNil, {~wSynthKeys.close});
		if(~wMeterAvail.notNil, {~wMeter.close});
		~wInOutAvail = nil;
	});

	// start system preferences display
	// "System_0.3.scd".loadRelative();

	// start controllers
	if(~wControllersAvail.isNil, {cfg.controllersFile.loadRelative});

	// start CueMix, Activity Monitor, s.meter
	if(cfg.startCueMix == 1, {"osascript -e 'tell application \"CueMix FX\" to activate'".unixCmd;});
	if(cfg.startActMon == 1, {"osascript -e 'tell application \"Activity Monitor\" to activate'".unixCmd;});
	if(cfg.startMOTUSetup == 1, {"osascript -e 'tell application \"MOTU Audio Setup\" to activate'".unixCmd;});
	if(cfg.startMeter == 1, {s.meter;});

}); // wait for boot

)

