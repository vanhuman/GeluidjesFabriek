// De Geluidjesfabriek
// controlling LiveSampler

// In startup for standalone
// {"/Users/Robert/---data---/audio/SC/GeluidjesFabriek_1.1.scd".load;}.defer(0.2);

(
s.waitForBoot({

	// ------- variables ------------------------------------------------------------------------------------------------------------------------

	var pID = 1; // project ID, index into project.name
	var project = (
		name: ["43","ZAAG55"],
		title: ["43","ZAAG55"],
		sampleLib: [
			"/Users/Robert/---data---/audio/projecten-a/43/Audio/",
			"/Users/Robert/---data---/audio/samples/ZAAG55/"
		],
		choiceList: [[3],[3]],			// number of repeats for each part, chosen randomly from this array
		fontHuge: [Font("Reprise Title Std",55),Font("Reprise Title Std",150)],
		fontBig: [Font("Reprise Title Std",55),Font("Reprise Title Std",47)],
		fontReg: [Font("Helvetica",16),Font("Helvetica",16)],
		fontSmall: [Font("Helvetica",10),Font("Helvetica",12)]
	);
	var cfg = (
		localAddr: NetAddr("127.0.0.1", 57120),
		version: "1.1",
		lengthFactor: 0.2, 									// all lengths are multiplied by this numner
		absRegOffset4: 0.005, //0.08					// offset in buffer for zone4
		deBug: 0,
		filterType: "aif,AIF,aiff,AIFF,wav,WAV",
		liveSamplerFile: "LiveSampler_10.3GF.scd",
		inOutFile: "InOut_1.6GF.scd",
		bangChannel: 1, 										// input channel for trigger
		bangLevel: -1, 											// threshold for trigger
		timeOutReset: 1, 									// time before the timeout will be reset
		autoTrigger: 0, 										// set to 1 to automatically trigger
		autoTriggerTime: 60, 								// wait time in sec to check if object is being generated

		project: project.name[pID],
		title: project.title[pID],
		sampleLib: project.sampleLib[pID],
		choiceList: project.choiceList[pID],
		fontHuge: project.fontHuge[pID],
		fontBig: project.fontBig[pID],
		fontReg: project.fontReg[pID],
		fontSmall: project.fontSmall[pID],
	);

	var fMachineWorkum, fMachineKoudum, fMachineMakkum, fMachineJoure, fMachineGrou, fSampleLoad, fLine, choice, task;
	var wGF, bMachineWorkum, bMachineKoudum, bMachineMakkum, bMachineJoure, bMachineGrou, bFolder, tFolder, tHeader, cRecord, tRecord, fButtonAction, wGF2, tProduction, bStop;
	var screenHeight = Window.screenBounds.height, screenWidth = Window.screenBounds.width;
	var files, filterTypeArray, filterName = "", filterNameArray, bFilterName, tFilterName, bCounter, fCounter, tCounter;
	var respTrigger, pTrigger, tTrigger, machineList = [\Geen, \Joure, \Makkum, \Workum, \Koudum, \Grou, \Random], triggerSynth = nil, timeOut = 0, bangProcessSynth = nil, buttonTriggered = nil;
	var buttonList, tAutoTrigger;

	// ------- SynthDef ------------------------------------------------------------------------------------------------------------------------

	SynthDef(\trigger, { arg chan = 0, dbThresh = -2;
		var trigOver, signal, amp, level;
		level = dbThresh.dbamp;
		signal = SoundIn.ar(chan);
		amp = Amplitude.kr(signal);
		trigOver = amp >= level;
		SendTrig.kr(trigOver, 1, amp);
	}).add;

	SynthDef(\bangProcess, { arg chan = 0, gate = 1;
		var sig;
		sig = SoundIn.ar(chan);
		sig = [AllpassC.ar(sig, 4,SinOsc.kr(0.5).range(0.23,0.115), 2), AllpassC.ar(sig, 4,SinOsc.kr(0.6).range(0.23,0.115), 2)];
		sig = sig * EnvGen.ar(Env.linen(0.01,3,1,1),gate,doneAction: 2);
		Out.ar(0,sig);
	}).add;


	// ------- OSC responders ------------------------------------------------------------------------------------------------------------------------

	OSCdef(\fabriekTrigger, {arg time, resp, msg;
		if(timeOut == 0, {
			"\n### Triggering".postln;
			timeOut = 1; {timeOut = 0}.defer(cfg.timeOutReset);
			bangProcessSynth = Synth(\bangProcess, [\chan,cfg.bangChannel]);
			{
				case
				{pTrigger.value == 1}
				{if(buttonTriggered.isNil,{bMachineJoure.valueAction_(1)},{buttonTriggered.valueAction_(0)})}
				{pTrigger.value == 2}
				{if(buttonTriggered.isNil,{bMachineMakkum.valueAction_(1)},{buttonTriggered.valueAction_(0)})}
				{pTrigger.value == 3}
				{if(buttonTriggered.isNil,{bMachineWorkum.valueAction_(1)},{buttonTriggered.valueAction_(0)})}
				{pTrigger.value == 4}
				{if(buttonTriggered.isNil,{bMachineKoudum.valueAction_(1)},{buttonTriggered.valueAction_(0)})}
				{pTrigger.value == 5}
				{if(buttonTriggered.isNil,{bMachineGrou.valueAction_(1)},{buttonTriggered.valueAction_(0)})}
				{pTrigger.value == 6} // Random
				{if(buttonTriggered.isNil,{buttonList.choose.valueAction_(1)},{buttonTriggered.valueAction_(0)})}
				;
			}.defer();
		}, {"\n### No triggering because of time-out".postln});
	}, '/tr').fix;

	// ------- functions ------------------------------------------------------------------------------------------------------------------------

		fMachineJoure = {

		// cfg.localAddr.sendMsg("/midi/control", chan - 1, ctr, value, "MUL");

		// zone3:
		//		start/level		chan 15 	ctr 4
		//		speed SP		chan 15 	ctr 6 (steps 0 0.25 0.5 0.75 1)
		//		speed amp	chan 15 	ctr 7
		//		filter				chan 13	ctr 97
		// zone4:
		//		start/level 	chan 12 	ctr 0
		//		abs regstart	chan 12	ctr 1
		// 		length 			chan 10 	ctr 40 (steps 0.2 0.4 0.6 0.8 1.0)
		//		filter				chan 10 	ctr 20
		//		pitch				chan 10	ctr 0

		// initialize LiveSampler
		cfg.localAddr.sendMsg("/quantize", 0, 30, 1); // quantize 1/0, bpm, debug 1/0

		// clear samplebuffer
		cfg.localAddr.sendMsg("/sampleload", "", 1, "");
		0.2.wait;

		// set parameters
		cfg.localAddr.sendMsg("/midi/control", 15 - 1, 6, 0, "MUL"); // zone3 speed SP
		cfg.localAddr.sendMsg("/midi/control", 15 - 1, 7, 1, "MUL"); // zone3 amp mod
		cfg.localAddr.sendMsg("/midi/control", 13 - 1, 97, 0, "MUL"); // zone3 filter
		cfg.localAddr.sendMsg("/midi/control", 10 - 1, 40, 0.3, "MUL"); // zone4 length loop
		cfg.localAddr.sendMsg("/midi/control", 10 - 1, 20, 0.3, "MUL"); // zone4 filter freq
		cfg.localAddr.sendMsg("/midi/control", 10 - 1, 0, 0.5, "MUL"); // zone4 pitch
		cfg.localAddr.sendMsg("/midi/control", 12 - 1, 1, cfg.absRegOffset4 + 0.52, "MUL"); // zone4 abs regstart

		// load initial samples
		fSampleLoad.value("B");
		fSampleLoad.value("A");
		0.1.wait;

		cfg.localAddr.sendMsg("/midi/control", 12 - 1, 0, 0.9, "MUL"); // zone4 play

		// part 1
		choice = cfg.choiceList.choose;
		("\n### Part 1:" + choice + "times").postln;
		choice.do({|i|
			(50*cfg.lengthFactor).wait;
			case
			{i == 0} {cfg.localAddr.sendMsg("/midi/control", 12 - 1, 1, cfg.absRegOffset4 + 0.525, "MUL"); "zone4 SP offset".postln} // zone4 abs regstart
			{i == 1} {cfg.localAddr.sendMsg("/midi/control", 12 - 1, 1, cfg.absRegOffset4 + 0.528, "MUL"); "zone4 SP offset".postln} // zone4 abs regstart
			{i == 2} {cfg.localAddr.sendMsg("/midi/control", 12 - 1, 1, cfg.absRegOffset4 + 0.53, "MUL"); "zone4 SP offset".postln} // zone4 abs regstart
			;
			(15*cfg.lengthFactor).wait;
			if(i == 2, {cfg.localAddr.sendMsg("/midi/control", 12 - 1, 0, 1, "MUL"); "zone4 play multiple".postln};); // zone4 play multiple
			(15*cfg.lengthFactor).wait;
			if(i==0, {fLine.value(10, 20,"Zone4 filter freq:",0.3,1,200,200)}); // zone4 ramp up filter freq
			(30*cfg.lengthFactor).wait;
		});

		cfg.localAddr.sendMsg("/midi/control", 15 - 1, 4, 1, "MUL"); // zone3 play

		// part 2
		choice = cfg.choiceList.choose;
		("\n### Part 2:" + choice + "times").postln;
		choice.do({|i|
			if(i >= 1, {fSampleLoad.value("A");});
			(40*cfg.lengthFactor).wait;
			if(i == 1, {cfg.localAddr.sendMsg("/midi/control", 12 - 1, 0, 0.9, "MUL"); "zone4 play single".postln}); // zone4 play single
			case
			{i == 0} {cfg.localAddr.sendMsg("/midi/control", 12 - 1, 1, cfg.absRegOffset4 + 0.525, "MUL"); "zone4 SP offset".postln} // zone4 abs regstart
			{i == 1} {cfg.localAddr.sendMsg("/midi/control", 12 - 1, 1, cfg.absRegOffset4 + 0.528, "MUL"); "zone4 SP offset".postln;} // zone4 abs regstart
			{i == 2} {cfg.localAddr.sendMsg("/midi/control", 12 - 1, 1, cfg.absRegOffset4 + 0.53, "MUL"); "zone4 SP offset".postln;} // zone4 abs regstart
			;
			(15*cfg.lengthFactor).wait;
			fLine.value(10, 0,"Zone4 pitch: ",0.5,1,90,90); // zone4 ramp up pitch
			(15*cfg.lengthFactor).wait;
			if(i >= 1, {fSampleLoad.value("B");});
			(30*cfg.lengthFactor).wait;
		});

		cfg.localAddr.sendMsg("/midi/control", 15 - 1, 7, 0.3, "MUL"); // zone3 amp mod

		// part 3
		choice = cfg.choiceList.choose;
		("\n### Part 3:" + choice + "times").postln;
		choice.do({|i|
			if(i >= 1, {fSampleLoad.value("A");});
			(60*cfg.lengthFactor).wait;
			if(i == 0, {cfg.localAddr.sendMsg("/midi/control", 12 - 1, 0, 1, "MUL"); "zone4 play multiple".postln}); // zone4 play multiple
			case
			{i == 0} {cfg.localAddr.sendMsg("/midi/control", 12 - 1, 1, cfg.absRegOffset4 + 0.535, "MUL"); "zone4 SP offset".postln;} // zone4 abs regstart
			{i == 1} {cfg.localAddr.sendMsg("/midi/control", 12 - 1, 1, cfg.absRegOffset4 + 0.538, "MUL"); "zone4 SP offset".postln;} // zone4 abs regstart
			{i == 2} {cfg.localAddr.sendMsg("/midi/control", 12 - 1, 1, cfg.absRegOffset4 + 0.54, "MUL"); "zone4 SP offset".postln;} // zone4 abs regstart
			;
			(30*cfg.lengthFactor).wait;
			fLine.value(10, 0,"Zone4 pitch: ",0.5,1,30,50); // zone4 ramp up pitch
			(25*cfg.lengthFactor).wait;
			if(i == 2, {cfg.localAddr.sendMsg("/midi/control", 12 - 1, 0, 0.9, "MUL"); "zone4 play single".postln}); // zone4 play single
			if(i == 1, {fLine.value(15, 7,"Zone3 amp mod: ",0.3,0.7,50,50)}); // zone3 amp mod
			fSampleLoad.value("B");
			(50*cfg.lengthFactor).wait;
		});

		cfg.localAddr.sendMsg("/midi/control", 15 - 1, 4, 0, "MUL"); // zone3 stop

		// part 4
		("\n### Part 4").postln;
		fLine.value(10,0,"Zone4 pitch: ",0.5,1,25,50); // zone4 ramp up pitch
		(25*cfg.lengthFactor).wait;
		fLine.value(10,0,"Zone4 pitch: ",1,0.5,25,50); // zone4 ramp up pitch
		(25*cfg.lengthFactor).wait;
		fLine.value(10,0,"Zone4 pitch: ",0.5,1,15,50); // zone4 ramp up pitch
		(15*cfg.lengthFactor).wait;
		fLine.value(10,0,"Zone4 pitch: ",1,0.5,25,50); // zone4 ramp up pitch
		(25*cfg.lengthFactor).wait;
		fLine.value(10,0,"Zone4 pitch: ",0.5,1,25,50); // zone4 ramp up pitch
		(25*cfg.lengthFactor).wait;
		fLine.value(10,0,"Zone4 pitch: ",1,0,60,50); // zone4 ramp up pitch
		(60*cfg.lengthFactor).wait;
		cfg.localAddr.sendMsg("/midi/control", 12 - 1, 1, cfg.absRegOffset4 + 0.55, "MUL"); "zone4 SP offset".postln;
		fLine.value(10,0,"Zone4 pitch: ",0.5,1,25,50); // zone4 ramp up pitch
		(25*cfg.lengthFactor).wait;
		fLine.value(10,0,"Zone4 pitch: ",1,0.5,25,50); // zone4 ramp up pitch
		(25*cfg.lengthFactor).wait;
		fLine.value(10,0,"Zone4 pitch: ",0.5,1,15,50); // zone4 ramp up pitch
		(15*cfg.lengthFactor).wait;
		fLine.value(10,0,"Zone4 pitch: ",1,0.5,25,50); // zone4 ramp up pitch
		(25*cfg.lengthFactor).wait;
		fLine.value(10,0,"Zone4 pitch: ",0.5,1,25,50); // zone4 ramp up pitch
		(25*cfg.lengthFactor).wait;
		fLine.value(10,0,"Zone4 pitch: ",1,0,60,50); // zone4 ramp up pitch
		(60*cfg.lengthFactor).wait;
		fLine.value(10, 20,"Zone4 filter freq:",1,0,30,60); // zone4 ramp up filter freq
		(60*cfg.lengthFactor).wait;

		cfg.localAddr.sendMsg("/midi/control", 12 - 1, 0, 0, "MUL"); // zone4 stop
		{bMachineJoure.valueAction_(0);}.defer();

	};

	fMachineMakkum = {

		// cfg.localAddr.sendMsg("/midi/control", chan - 1, ctr, value, "MUL");

		// zone3:
		//		start/level		chan 15 	ctr 4
		//		speed SP		chan 15 	ctr 6 (steps 0 0.25 0.5 0.75 1)
		//		speed amp	chan 15 	ctr 7
		//		filter				chan 13	ctr 97
		// zone4:
		//		start/level 	chan 12 	ctr 0
		//		abs regstart	chan 12	ctr 1
		// 		length 			chan 10 	ctr 40 (steps 0.2 0.4 0.6 0.8 1.0)
		//		filter				chan 10 	ctr 20
		//		pitch				chan 10	ctr 0

		// initialize LiveSampler
		cfg.localAddr.sendMsg("/quantize", 1, 90, 1); // quantize 1/0, bpm, debug 1/0

		// clear samplebuffer
		cfg.localAddr.sendMsg("/sampleload", "", 1, "");
		0.2.wait;

		// set parameters
		cfg.localAddr.sendMsg("/midi/control", 15 - 1, 6, 1, "MUL"); // zone3 speed SP
		cfg.localAddr.sendMsg("/midi/control", 15 - 1, 7, 1, "MUL"); // zone3 amp mod
		cfg.localAddr.sendMsg("/midi/control", 13 - 1, 97, 0, "MUL"); // zone3 filter
		cfg.localAddr.sendMsg("/midi/control", 10 - 1, 40, 1, "MUL"); // zone4 length loop
		cfg.localAddr.sendMsg("/midi/control", 10 - 1, 20, 0.5, "MUL"); // zone4 filter freq
		cfg.localAddr.sendMsg("/midi/control", 10 - 1, 0, 0.5, "MUL"); // zone4 pitch
		cfg.localAddr.sendMsg("/midi/control", 12 - 1, 1, cfg.absRegOffset4 + 0.52, "MUL"); // zone4 abs regstart

		// load initial samples
		fSampleLoad.value("B");
		fSampleLoad.value("A");
		0.1.wait;

		cfg.localAddr.sendMsg("/midi/control", 12 - 1, 0, 0.9, "MUL"); // zone4 play

		// part 1
		choice = cfg.choiceList.choose;
		("\n### Part 1:" + choice + "times").postln;
		choice.do({|i|
			if(i >= 1, {fSampleLoad.value("B");});
			(50*cfg.lengthFactor).wait;
			if(i == 0,
				{cfg.localAddr.sendMsg("/midi/control", 12 - 1, 1, cfg.absRegOffset4 + 0.53, "MUL");}, // zone4 abs regstart
				{cfg.localAddr.sendMsg("/midi/control", 12 - 1, 1, cfg.absRegOffset4 + 0.55, "MUL");}); // zone4 abs regstart
			(15*cfg.lengthFactor).wait;
			if(i == 2, {cfg.localAddr.sendMsg("/midi/control", 12 - 1, 0, 1, "MUL")}); // zone4 play multiple
			(15*cfg.lengthFactor).wait;
			fLine.value(10, 20,"Zone4 filter freq:",0.2,0.8,20,50); // zone4 ramp up filter freq
			(30*cfg.lengthFactor).wait;
		});

		cfg.localAddr.sendMsg("/midi/control", 15 - 1, 4, 1, "MUL"); // zone3 play

		// part 2
		choice = cfg.choiceList.choose;
		("\n### Part 2:" + choice + "times").postln;
		choice.do({|i|
			if(i >= 1, {fSampleLoad.value("A");});
			(40*cfg.lengthFactor).wait;
			if(i == 1, {cfg.localAddr.sendMsg("/midi/control", 12 - 1, 0, 0.9, "MUL")}); // zone4 play single
			if(i == 0,
				{cfg.localAddr.sendMsg("/midi/control", 12 - 1, 1, cfg.absRegOffset4 + 0.53, "MUL");}, // zone4 abs regstart
				{cfg.localAddr.sendMsg("/midi/control", 12 - 1, 1, cfg.absRegOffset4 + 0.55, "MUL");}); // zone4 abs regstart
			(15*cfg.lengthFactor).wait;
			fLine.value(10, 0,"Zone4 pitch: ",0.5,1,9,50); // zone4 ramp up pitch
			(15*cfg.lengthFactor).wait;
			fLine.value(15,7,"Zone3 amp mod:",1,0.7,1,50); // zone3 ramp up amp mod
			fSampleLoad.value("B");
			(30*cfg.lengthFactor).wait;
		});

		cfg.localAddr.sendMsg("/midi/control", 15 - 1, 6, 0.5, "MUL"); // zone3 speed SP
		cfg.localAddr.sendMsg("/midi/control", 15 - 1, 7, 0.5, "MUL"); // zone3 amp mod

		// part 3
		choice = cfg.choiceList.choose;
		("\n### Part 3:" + choice + "times").postln;
		choice.do({|i|
			if(i >= 1, {fSampleLoad.value("A");});
			(30*cfg.lengthFactor).wait;
			if(i == 0, {cfg.localAddr.sendMsg("/midi/control", 12 - 1, 0, 1, "MUL")}); // zone4 play multiple
			if(i == 0,
				{cfg.localAddr.sendMsg("/midi/control", 12 - 1, 1, cfg.absRegOffset4 + 0.53, "MUL");}, // zone4 abs regstart
				{cfg.localAddr.sendMsg("/midi/control", 12 - 1, 1, cfg.absRegOffset4 + 0.55, "MUL");}); // zone4 abs regstart
			(15*cfg.lengthFactor).wait;
			fLine.value(10, 0,"Zone4 pitch: ",0.5,1,9,50); // zone4 ramp up pitch
			(15*cfg.lengthFactor).wait;
			if(i == 2, {cfg.localAddr.sendMsg("/midi/control", 12 - 1, 0, 0.9, "MUL")}); // zone4 play single
			fSampleLoad.value("B");
			(30*cfg.lengthFactor).wait;
		});

		cfg.localAddr.sendMsg("/midi/control", 15 - 1, 7, 1, "MUL"); // zone3 amp mod

		// part 4
		choice = cfg.choiceList.choose;
		("\n### Part 4:" + choice + "times").postln;
		fLine.value(13,97,"Zone3 filter freq:",0,0.6,150,200); // zone3 ramp up filter freq
		choice.do({|i|
			if(i == 1, {fSampleLoad.value("A");});
			(30*cfg.lengthFactor).wait;
			if(i == 0,
				{cfg.localAddr.sendMsg("/midi/control", 12 - 1, 1, cfg.absRegOffset4 + 0.53, "MUL");}, // zone4 abs regstart
				{cfg.localAddr.sendMsg("/midi/control", 12 - 1, 1, cfg.absRegOffset4 + 0.55, "MUL");}); // zone4 abs regstart
			(15*cfg.lengthFactor).wait;
			(15*cfg.lengthFactor).wait;
			fSampleLoad.value("B");
			(30*cfg.lengthFactor).wait;
		});

		// part 5
		("\n### Part 5").postln;
		cfg.localAddr.sendMsg("/midi/control", 15 - 1, 4, 0, "MUL"); // zone3 stop
		fLine.value(10,0,"Zone4 pitch: ",0.5,1,5,50); // zone4 ramp up pitch
		(5*cfg.lengthFactor).wait;
		fLine.value(10,0,"Zone4 pitch: ",1,0.5,5,50); // zone4 ramp up pitch
		(5*cfg.lengthFactor).wait;
		fLine.value(10,0,"Zone4 pitch: ",0.5,1,5,50); // zone4 ramp up pitch
		(5*cfg.lengthFactor).wait;
		fLine.value(10,0,"Zone4 pitch: ",1,0.5,5,50); // zone4 ramp up pitch
		(5*cfg.lengthFactor).wait;
		fLine.value(10,0,"Zone4 pitch: ",0.5,1,5,50); // zone4 ramp up pitch
		(5*cfg.lengthFactor).wait;
		fLine.value(10,0,"Zone4 pitch: ",1,0.5,60,50); // zone4 ramp up pitch
		(60*cfg.lengthFactor).wait;
		fLine.value(10, 20,"Zone4 filter freq:",1,0,30,60); // zone4 ramp up filter freq
		(60*cfg.lengthFactor).wait;

		cfg.localAddr.sendMsg("/midi/control", 12 - 1, 0, 0, "MUL"); // zone4 stop
		{bMachineMakkum.valueAction_(0);}.defer();

	};

	fMachineWorkum = {

		// initialize LiveSampler
		cfg.localAddr.sendMsg("/quantize", 1, 120, 1); // quantize 1/0, bpm, debug 1/0

		// clear samplebuffer
		cfg.localAddr.sendMsg("/sampleload", "", 1, "");
		0.2.wait;

		// set parameters
		cfg.localAddr.sendMsg("/midi/control", 15 - 1, 6, 0, "MUL"); // zone3 speed SP
		cfg.localAddr.sendMsg("/midi/control", 15 - 1, 7, 1, "MUL"); // zone3 amp mod
		cfg.localAddr.sendMsg("/midi/control", 10 - 1, 40, 1, "MUL"); // zone4 length loop
		cfg.localAddr.sendMsg("/midi/control", 10 - 1, 20, 0.2, "MUL"); // zone4 filter freq
		cfg.localAddr.sendMsg("/midi/control", 10 - 1, 0, 0.5, "MUL"); // zone4 pitch
		cfg.localAddr.sendMsg("/midi/control", 12 - 1, 1, cfg.absRegOffset4 + 0.52, "MUL"); // zone4 abs regstart

		// load initial samples
		fSampleLoad.value("B");
		fSampleLoad.value("A");
		0.1.wait;

		cfg.localAddr.sendMsg("/midi/control", 12 - 1, 0, 0.9, "MUL"); // zone4 play

		// part 1
		choice = cfg.choiceList.choose;
		("\n### Part 1:" + choice + "times").postln;
		choice.do({|i|
			if(i >= 1, {fSampleLoad.value("B");});
			(12*cfg.lengthFactor).wait;
			if(i == 0,
				{cfg.localAddr.sendMsg("/midi/control", 12 - 1, 1, cfg.absRegOffset4 + 0.53, "MUL");}, // zone4 abs regstart
				{cfg.localAddr.sendMsg("/midi/control", 12 - 1, 1, cfg.absRegOffset4 + 0.55, "MUL");}); // zone4 abs regstart
			(3*cfg.lengthFactor).wait;
			fLine.value(10, 0,"Zone4 pitch: ",0.5,1,9,50); // zone4 ramp up pitch
			(3*cfg.lengthFactor).wait;
			fLine.value(10, 20,"Zone4 filter freq:",0.2,0.8,6,50); // zone4 ramp up filter freq
			(6*cfg.lengthFactor).wait;
		});

		cfg.localAddr.sendMsg("/midi/control", 15 - 1, 4, 1, "MUL"); // zone3 play
		fLine.value(15,7,"Zone3 amp mod:",1,0.7,1,50); // zone3 ramp up amp mod

		// part 2
		choice = cfg.choiceList.choose;
		("\n### Part 2:" + choice + "times").postln;
		choice.do({|i|
			if(i >= 1, {fSampleLoad.value("B");});
			(12*cfg.lengthFactor).wait;
			cfg.localAddr.sendMsg("/midi/control", 12 - 1, 1, cfg.absRegOffset4 + 0.57, "MUL"); // zone4 abs regstart
			fLine.value(13,97,"Zone3 filter freq:",0,0.8,3,50); // zone3 ramp up filter freq
			(3*cfg.lengthFactor).wait;
			fLine.value(10,0,"Zone4 pitch: ",0.5,0,2,50); // zone4 ramp up pitch
			fLine.value(13,97,"Zone3 filter freq:",0.8,0.5,4,50); // zone3 ramp up filter freq
			(4*cfg.lengthFactor).wait;
			fLine.value(10,0,"Zone4 pitch: ",0,0.7,5,50); // zone4 ramp up pitch
			(5*cfg.lengthFactor).wait;
			fLine.value(13,97,"Zone3 filter freq:",0.5,0,6,50); // zone3 ramp up filter freq
			(6*cfg.lengthFactor).wait;
		});

		// part 3
		choice = cfg.choiceList.choose;
		("\n### Part 3:" + choice + "times").postln;
		choice.do({|i|
			cfg.localAddr.sendMsg("/midi/control", 10 - 1, 40, 0.8, "MUL"); // zone4 speed loop
			fSampleLoad.value("B");
			fLine.value(13,97,"Zone3 filter freq:",0,0.5,12,100); // zone3 ramp up filter freq
			(12*cfg.lengthFactor).wait;
			cfg.localAddr.sendMsg("/midi/control", 12 - 1, 1, cfg.absRegOffset4 + 0.59, "MUL"); // zone4 abs regstart
			(2*cfg.lengthFactor).wait;
			fLine.value(10,0,"Zone4 pitch: ",0.7,0,5,50); // zone4 ramp up pitch
			(5*cfg.lengthFactor).wait;
			fLine.value(10,0,"Zone4 pitch: ",0,1,1,50); // zone4 ramp up pitch
			(5*cfg.lengthFactor).wait;
			fLine.value(13,97,"Zone3 filter freq:",0.5,0,6,100); // zone3 ramp up filter freq
			(6*cfg.lengthFactor).wait;
		});

		// part 4
		choice = cfg.choiceList.choose;
		("\n### Part 4:" + choice + "times").postln;
		choice.do({|i|
			cfg.localAddr.sendMsg("/midi/control", 15 - 1, 6, 0.25, "MUL"); // zone3 speed SP
			fSampleLoad.value("A");
			fLine.value(15,7,"Zone3 amp mod:",0.7,1,5,50); // zone3 ramp up amp mod
			(12*cfg.lengthFactor).wait;
			cfg.localAddr.sendMsg("/midi/control", 12 - 1, 1, cfg.absRegOffset4 + 0.62, "MUL"); // zone4 abs regstart
			(1*cfg.lengthFactor).wait;
			fLine.value(10,0,"Zone4 pitch: ",0.5,1,5,5); // zone4 ramp up pitch
			(11*cfg.lengthFactor).wait;
		});

		// part 5
		choice = cfg.choiceList.choose;
		("\n### Part 5:" + choice + "times").postln;
		choice.do({|i|
			cfg.localAddr.sendMsg("/midi/control", 10 - 1, 40, 0.6, "MUL"); // zone4 speed loop
			fSampleLoad.value("B");
			(12*cfg.lengthFactor).wait;
			cfg.localAddr.sendMsg("/midi/control", 12 - 1, 1, cfg.absRegOffset4 + 0.65, "MUL"); // zone4 abs regstart
			(3*cfg.lengthFactor).wait;
			fLine.value(10,0,"Zone4 pitch: ",0.5,1,1,50); // zone4 ramp up pitch
			(1*cfg.lengthFactor).wait;
			fLine.value(10,0,"Zone4 pitch: ",1,0.5,1,50); // zone4 ramp up pitch
			(1*cfg.lengthFactor).wait;
			fLine.value(10,0,"Zone4 pitch: ",0.5,1,1,50); // zone4 ramp up pitch
			(1*cfg.lengthFactor).wait;
			fLine.value(10,0,"Zone4 pitch: ",1,0.5,1,50); // zone4 ramp up pitch
			(1*cfg.lengthFactor).wait;
			fLine.value(10,0,"Zone4 pitch: ",0.5,1,1,50); // zone4 ramp up pitch
			(1*cfg.lengthFactor).wait;
			fLine.value(10,0,"Zone4 pitch: ",1,0.5,3,50); // zone4 ramp up pitch
			(4*cfg.lengthFactor).wait;
		});

		// part 6
		choice = cfg.choiceList.choose;
		("\n### Part 6:" + choice + "times").postln;
		choice.do({|i|
			cfg.localAddr.sendMsg("/midi/control", 15 - 1, 6, 0.5, "MUL"); // zone3 speed SP
			fSampleLoad.value("A");
			(12*cfg.lengthFactor).wait;
			cfg.localAddr.sendMsg("/midi/control", 12 - 1, 1, cfg.absRegOffset4 + 0.67, "MUL"); // zone4 abs regstart
			fLine.value(13,97,"Zone3 filter freq:",0,0.8,5,4); // zone3 ramp up filter freq
			(2*cfg.lengthFactor).wait;
			fLine.value(10,0,"Zone4 pitch: ",0.5,0,5,5); // zone4 ramp up pitch
			(5*cfg.lengthFactor).wait;
			fLine.value(10,0,"Zone4 pitch: ",0,0.8,1,50); // zone4 ramp up pitch
			fLine.value(13,97,"Zone3 filter freq:",0.8,0.5,3,3); // zone3 ramp up filter freq
			(5*cfg.lengthFactor).wait;
			fLine.value(13,97,"Zone3 filter freq:",0.5,0,3,3); // zone3 ramp up filter freq
		});

		// part 7
		choice = cfg.choiceList.choose;
		("\n### Part 7:" + choice + "times").postln;
		choice.do({|i|
			cfg.localAddr.sendMsg("/midi/control", 10 - 1, 40, 0.4, "MUL"); // zone4 speed loop
			fSampleLoad.value("B");
			(12*cfg.lengthFactor).wait;
			cfg.localAddr.sendMsg("/midi/control", 12 - 1, 1, cfg.absRegOffset4 + 0.69, "MUL"); // zone4 abs regstart
			(12*cfg.lengthFactor).wait;
		});

		fLine.value(15,7,"Zone3 amp mod:",1,0.9,1,50); // zone3 ramp up amp mod

		// part 8
		choice = cfg.choiceList.choose;
		("\n### Part 8:" + choice + "times").postln;
		choice.do({|i|
			cfg.localAddr.sendMsg("/midi/control", 15 - 1, 6, 0.75, "MUL"); // zone3 speed SP
			fSampleLoad.value("A");
			(12*cfg.lengthFactor).wait;
			cfg.localAddr.sendMsg("/midi/control", 12 - 1, 1, cfg.absRegOffset4 + 0.72, "MUL"); // zone4 abs regstart
			(3*cfg.lengthFactor).wait;
			fLine.value(10,0,"Zone4 pitch: ",0.8,0.5,5,5); // zone4 ramp up pitch
			(9*cfg.lengthFactor).wait;
		});

		fLine.value(15,7,"Zone3 amp mod:",0.9,0.7,1,50); // zone3 ramp up amp mod

		// part 9
		choice = cfg.choiceList.choose;
		("\n### Part 9:" + choice + "times").postln;
		choice.do({|i|
			cfg.localAddr.sendMsg("/midi/control", 10 - 1, 40, 0.2, "MUL"); // zone4 speed loop
			fSampleLoad.value("B");
			fLine.value(13,97,"Zone3 filter freq:",0,0.5,15,500); // zone3 ramp up filter freq
			(12*cfg.lengthFactor).wait;
			cfg.localAddr.sendMsg("/midi/control", 12 - 1, 1, cfg.absRegOffset4 + 0.75, "MUL"); // zone4 abs regstart
			(6*cfg.lengthFactor).wait;
			fLine.value(13,97,"Zone3 filter freq:",0.5,0.8,2,50); // zone3 ramp up filter freq
			(3*cfg.lengthFactor).wait;
			fLine.value(13,97,"Zone3 filter freq:",0.8,0,2,2); // zone3 ramp up filter freq
			(3*cfg.lengthFactor).wait;
		});

		fLine.value(13,97,"Zone3 filter freq:",0,0.5,15,1500); // zone3 ramp up filter freq

		// part 10
		choice = cfg.choiceList.choose;
		("\n### Part 10:" + choice + "times").postln;
		choice.do({|i|
			cfg.localAddr.sendMsg("/midi/control", 15 - 1, 6, 1, "MUL"); // zone3 speed SP
			fSampleLoad.value("A");
			(12*cfg.lengthFactor).wait;
			cfg.localAddr.sendMsg("/midi/control", 12 - 1, 1, cfg.absRegOffset4 + 0.77, "MUL"); // zone4 abs regstart
			(2*cfg.lengthFactor).wait;
			fLine.value(10,0,"Zone4 pitch: ",0.5,0,5,5); // zone4 ramp up pitch
			(5*cfg.lengthFactor).wait;
			fLine.value(10,0,"Zone4 pitch: ",0,0.8,1,50); // zone4 ramp up pitch
			(5*cfg.lengthFactor).wait;
		});

		cfg.localAddr.sendMsg("/midi/control", 15 - 1, 4, 0, "MUL"); // zone3 stop

		// part 11
		choice = cfg.choiceList.choose;
		("\n### Part 11:" + choice + "times").postln;
		choice.do({|i|
			fSampleLoad.value("B");
			(3*cfg.lengthFactor).wait;
			fLine.value(10,0,"Zone4 pitch: ",0.5,0,2,50); // zone4 ramp up pitch
			(4*cfg.lengthFactor).wait;
			fLine.value(10,0,"Zone4 pitch: ",0,0.7,5,50); // zone4 ramp up pitch
			(5*cfg.lengthFactor).wait;
			cfg.localAddr.sendMsg("/midi/control", 12 - 1, 1, cfg.absRegOffset4 + 0.8, "MUL"); // zone4 abs regstart
			fLine.value(10, 20,"Zone4 filter freq:",0.8,0.2,6,50); // zone4 ramp up filter freq
			(12*cfg.lengthFactor).wait;
		});

		cfg.localAddr.sendMsg("/midi/control", 12 - 1, 0, 0, "MUL"); // zone4 stop
		{bMachineWorkum.valueAction_(0);}.defer();

	};

	fMachineKoudum = {

		// initialize LiveSampler
		cfg.localAddr.sendMsg("/quantize", 1, 120, 1); // quantize 1/0, bpm, debug 1/0

		// clear samplebuffer
		cfg.localAddr.sendMsg("/sampleload", "", 1, "");
		0.2.wait;

		// set parameters
		cfg.localAddr.sendMsg("/midi/control", 15 - 1, 6, 0, "MUL"); // zone3 speed SP
		cfg.localAddr.sendMsg("/midi/control", 15 - 1, 7, 1, "MUL"); // zone3 amp mod
		cfg.localAddr.sendMsg("/midi/control", 10 - 1, 40, 1, "MUL"); // zone4 length loop
		cfg.localAddr.sendMsg("/midi/control", 10 - 1, 20, 0.2, "MUL"); // zone4 filter freq
		cfg.localAddr.sendMsg("/midi/control", 10 - 1, 0, 0.5, "MUL"); // zone4 pitch
		cfg.localAddr.sendMsg("/midi/control", 12 - 1, 1, cfg.absRegOffset4 + 0.52, "MUL"); // zone4 abs regstart

		// load initial samples
		fSampleLoad.value("B");
		fSampleLoad.value("A");
		0.1.wait;

		cfg.localAddr.sendMsg("/midi/control", 12 - 1, 0, 0.9, "MUL"); // zone4 play

		// part 1
		choice = cfg.choiceList.choose;
		("\n### Part 11:" + choice + "times").postln;
		choice.do({|i|
			fSampleLoad.value("B");
			(3*cfg.lengthFactor).wait;
			fLine.value(10,0,"Zone4 pitch: ",0.5,0,2,50); // zone4 ramp up pitch
			(4*cfg.lengthFactor).wait;
			fLine.value(10,0,"Zone4 pitch: ",0,0.7,5,50); // zone4 ramp up pitch
			(5*cfg.lengthFactor).wait;
			cfg.localAddr.sendMsg("/midi/control", 12 - 1, 1, cfg.absRegOffset4 + 0.8, "MUL"); // zone4 abs regstart
			fLine.value(10, 20,"Zone4 filter freq:",0.8,0.2,6,50); // zone4 ramp up filter freq
			(12*cfg.lengthFactor).wait;
		});

		cfg.localAddr.sendMsg("/midi/control", 12 - 1, 0, 0, "MUL"); // zone4 stop
		{bMachineKoudum.valueAction_(0);}.defer();

	};

	fMachineGrou = {

		// cfg.localAddr.sendMsg("/midi/control", chan - 1, ctr, value, "MUL");

		// zone3:
		//		start/level		chan 15 	ctr 4
		//		speed SP		chan 15 	ctr 6 (steps 0 0.25 0.5 0.75 1)
		//		speed amp	chan 15 	ctr 7
		//		filter				chan 13	ctr 97
		// zone4:
		//		start/level 	chan 12 	ctr 0
		//		abs regstart	chan 12	ctr 1
		// 		length 			chan 10 	ctr 40 (steps 0.2 0.4 0.6 0.8 1.0)
		//		filter				chan 10 	ctr 20
		//		pitch				chan 10	ctr 0

		// initialize LiveSampler
		cfg.localAddr.sendMsg("/quantize", 0, 200, 0); // quantize 1/0, bpm, debug 1/0

		// clear samplebuffer
		cfg.localAddr.sendMsg("/sampleload", "", 1, "");
		0.2.wait;

		// set parameters
		cfg.localAddr.sendMsg("/midi/control", 15 - 1, 6, 0, "MUL"); // zone3 speed SP
		cfg.localAddr.sendMsg("/midi/control", 15 - 1, 7, 1, "MUL"); // zone3 amp mod
		cfg.localAddr.sendMsg("/midi/control", 10 - 1, 40, 0.3, "MUL"); // zone4 length loop
		cfg.localAddr.sendMsg("/midi/control", 10 - 1, 20, 0.5, "MUL"); // zone4 filter freq
		cfg.localAddr.sendMsg("/midi/control", 10 - 1, 0, 0.5, "MUL"); // zone4 pitch
		cfg.localAddr.sendMsg("/midi/control", 12 - 1, 1, cfg.absRegOffset4 + 0.52, "MUL"); // zone4 abs regstart

		// load initial samples
		fSampleLoad.value("B");
		fSampleLoad.value("A");
		0.1.wait;

		cfg.localAddr.sendMsg("/midi/control", 15 - 1, 4, 1, "MUL"); // zone3 play

		fLine.value(15, 6,"Zone3 speed SP:",0,1,15,50); // zone3 ramp up speed SP
		fLine.value(15,7,"Zone3 amp mod:",1,0.7,10,50); // zone3 ramp up amp mod
		fLine.value(13,97,"Zone3 filter:",0,0.6,10,50); // zone3 ramp up amp mod
		0.5.wait;
		cfg.localAddr.sendMsg("/midi/control", 12 - 1, 0, 0.9, "MUL"); // zone4 play
		fLine.value(12,1,"Zone4 SP offset:",0.52,0.7,15,50); // zone4 ramp up SP offset
		fLine.value(10,20,"Zone4 filter freq:",0.2,1,10,50); // zone4 ramp up filter freq
		1.wait;
		cfg.localAddr.sendMsg("/midi/control", 12 - 1, 0, 1, "MUL"); // zone4 play
		fLine.value(10,40,"Zone4 length:",0.2,0.001,5,50); // zone4 ramp up length
		1.5.wait;
		fSampleLoad.value("B");
		0.5.wait;

		cfg.localAddr.sendMsg("/midi/control", 15 - 1, 4, 0, "MUL"); // zone3 stop
		cfg.localAddr.sendMsg("/midi/control", 12 - 1, 0, 0, "MUL"); // zone4 stop
		{bMachineGrou.valueAction_(0);}.defer();

	};
	fSampleLoad = {
		arg bufPart;
		var soundFile, soundFileList = "", fileFound = 0, numFramesTotal = 0;

		("\nLoad sample in buffer part" + bufPart).postln;
		f = SoundFile.new;
		while(
			{fileFound == 0},
			{
				soundFile = files.choose;
				if(f.openRead(soundFile),
					{
						soundFile.postln;
						("Sample length" + (f.numFrames / s.sampleRate)).postln;
						numFramesTotal = numFramesTotal + f.numFrames;
						soundFileList = soundFileList ++ if(soundFileList=="",{""},{","}) ++ soundFile;
						if((numFramesTotal / s.sampleRate) >= 40, {fileFound = 1});
				});
		});
		f.close;

		cfg.localAddr.sendMsg("/sampleload",
			soundFileList,
			0, // normalize (note: this normalizes the whole buffer!)
			bufPart, // buffer part to load in
			0 // sample path is alsolute(0) / relative(1)
		);
	};

	fLine = {
		arg chan, ctr, post, start, end, duration, step;
		var tLine;

		duration = duration * cfg.lengthFactor;

		("\n"++post + "start value" + start + ", duration" + duration + ", steps" + step).postln;
		tLine = Task.new({
			step.do({arg i;
				cfg.localAddr.sendMsg("/midi/control", chan - 1, ctr, start + (i*((end-start)/step)), "MUL");
				(duration/step).wait;
				if(cfg.deBug == 1, {(post + (start + (i*((end-start)/step)))).postln});
			});
		});
		tLine.start;
		{
			tLine.stop;
			("\n"++post + "end value" + end).postln;
		}.defer(duration + 0.2);
	};

	fButtonAction = {
		arg button, function;

		if(button.value == 1,
			{
				("\n###"+button.states[0][0]).postln;
				("\nGrondstof Locatie:" + cfg.sampleLib).postln;
				("Grondstof Filter:" + cfg.filterType).postln;

				// fill files array with all soundfiles
				filterTypeArray = cfg.filterType.split($,);
				filterNameArray = filterName.replace(", ",",").split($,); // get rid of trailing spaces

				files = Array.newClear;
				filterTypeArray.size.do({|i|
					filterNameArray.size.do({|j|
						("Selecteer files op" + cfg.sampleLib ++ filterNameArray[j] ++ if(filterTypeArray[i]=="",{"*"},{"*."}) ++ filterTypeArray[i]).postln;
						files = files ++ (   cfg.sampleLib ++ filterNameArray[j] ++ if(filterTypeArray[i]=="",{"*"},{"*."}) ++ filterTypeArray[i]   ).pathMatch;
					});
				});
				if(files[0].notNil,
					{
						if(cRecord.value, {s.record; "Recording".postln;});
						cRecord.enabled_(false);
						bFolder.enabled_(false);
						tFolder.enabled_(false);
						bFilterName.enabled_(false);
						tFilterName.enabled_(false);
						case
						{button == bMachineMakkum}
						{bMachineGrou.enabled_(false); bMachineKoudum.enabled_(false); bMachineWorkum.enabled_(false); bMachineJoure.enabled_(false)}
						{button == bMachineKoudum}
						{bMachineGrou.enabled_(false); bMachineMakkum.enabled_(false); bMachineWorkum.enabled_(false); bMachineJoure.enabled_(false)}
						{button == bMachineWorkum}
						{bMachineGrou.enabled_(false); bMachineKoudum.enabled_(false); bMachineMakkum.enabled_(false); bMachineJoure.enabled_(false)}
						{button == bMachineJoure}
						{bMachineGrou.enabled_(false); bMachineKoudum.enabled_(false); bMachineMakkum.enabled_(false); bMachineWorkum.enabled_(false)}
						{button == bMachineGrou}
						{bMachineJoure.enabled_(false); bMachineKoudum.enabled_(false); bMachineMakkum.enabled_(false); bMachineWorkum.enabled_(false)}
						;
						tProduction.string = "In productie: \n\n" ++ button.states[0][0].asString.subStr(18,100) ++ if(cRecord.value, {"\n\nUitvoer bewaard"},{"\n\n"});
						bCounter.stringColor_(Color.red);
						task = Task(function).play;
						tCounter = Task(fCounter).play;
						buttonTriggered = button; // for automatic triggering
					},
					{
						("FOUT: Geen grondstoffen in locatie" + cfg.sampleLib + "die voldoen aan filter" + cfg.filterType ++ ".").postln;
						{button.valueAction_(0)}.defer(0.5);
					}
				);
			},
			{
				("\n###"+button.states[1][0]).postln;
				task.stop;
				tCounter.stop;
				cRecord.enabled_(true);
				bFolder.enabled_(true);
				tFolder.enabled_(true);
				bFilterName.enabled_(true);
				tFilterName.enabled_(true);
				bMachineKoudum.enabled_(true); bMachineWorkum.enabled_(true); bMachineMakkum.enabled_(true); bMachineJoure.enabled_(true); bMachineGrou.enabled_(true);
				tProduction.string = "Productie gestopt: \n\n" ++ button.states[0][0].asString.subStr(18,100) ++ if(cRecord.value, {"\n\nUitvoer bewaard"},{"\n\n"});
				bCounter.stringColor_(Color.grey(0.3));
				if(cRecord.value, {{s.stopRecording}.defer(1)});
				buttonTriggered = nil; // for automatic triggering
				cfg.localAddr.sendMsg("/midi/control", 15 - 1, 4, 0, "MUL");
				cfg.localAddr.sendMsg("/midi/control", 12 - 1, 0, 0, "MUL");
		});
	};

	fCounter = {
		inf.do {
			arg count;
			{bCounter.string_(count.asTimeStringHM)}.defer();
			1.wait;
		};
	};

	tAutoTrigger = Task({
		inf.do({
			cfg.autoTriggerTime.wait;
			"\nWordt er een geluidobject geproduceerd?".postln;
			{
				if(buttonTriggered.isNil,{
					"Nee. Start een nieuwe.".postln;
					buttonList.choose.valueAction_(1);
				},{
						"Ja. Wacht rustig af.".postln;
				})
			}.defer();
		});
	});

	// ------- GUI ------------------------------------------------------------------------------------------------------------------------

	wGF = Window("GeluidjesFabriek" + cfg.version + cfg.title, Rect(50, (screenHeight - 750), 550, 700));

	// header text
	(tHeader = StaticText(wGF,Rect(30, 20, 500, 60))
		.stringColor_(Color.grey(0.3))
		.font_(cfg.fontBig)
		.string_("GeluidjesFabriek" + cfg.title)
		.setProperty(\align, \center));

	// file location
	bFolder = (Button(wGF, Rect(30, 100, 130, 20))
		.states_([["Locatie basisgeluiden", Color.white, Color(0,0,0.7,0.7)]])
		.font_(cfg.fontSmall)
		.action_({
			Dialog.openPanel(
				{
					arg path;
					cfg.sampleLib = path.subStr(0, path.findBackwards("/"));
					("\nLocatie:" + cfg.sampleLib).postln;
					tFolder.string = if(cfg.sampleLib.size < 55,
						{cfg.sampleLib},{if(cfg.sampleLib.size==55, {""},{"..."}) ++ cfg.sampleLib.subStr(cfg.sampleLib.size - 55)});
				},
				{"\nGeen bestanden geselecteerd.".postln},
				false
			);
	}));
	tFolder = (TextField(wGF,Rect(170, 100, 340, 20))
		.stringColor_(Color.black)
		.font_(Font("Monaco",9))
		.string_(cfg.sampleLib)
		.background_(Color(1,1,1,0.8))
		.action_({
			cfg.sampleLib = tFolder.value;
			("\nLocatie:" + cfg.sampleLib).postln;
	}));
	tFolder.setProperty(\align, \center);

	bFilterName = (Button(wGF, Rect(30, 130, 130, 20))
		.states_([
			["Filter op naam", Color.white, Color(0,0,0.7,0.7)]
		])
		.font_(cfg.fontSmall)
		.action_({
			Dialog.openPanel(
				{
					arg path;
					filterName = path.subStr(path.findBackwards("/")+1,path.findBackwards(".")-1);
					("\nFilter op naam:" + filterName).postln;
					tFilterName.string = filterName;
				},
				{"\nGeen bestanden geselecteerd.".postln},
				false
			);
	}));

	tFilterName = (TextField(wGF,Rect(170, 130, 340, 20))
		.stringColor_(Color.black)
		.font_(Font("Monaco",9))
		.string_(filterName)
		.background_(Color(1,1,1,0.8))
		.action_({
			filterName = tFilterName.value;
			("Filter:" + filterName).postln;
	}));
	tFilterName.setProperty(\align, \center);

	// stop button
	bStop = (SmoothButton(wGF, Rect(30,200,100,100))
		.radius_(100)
		.border_(0)
		.font_(cfg.fontReg)
		.canFocus_(false)
		.states_([["NOODSTOP", Color.white, Color.red]])
		.action_({
			"osascript -e 'tell application \"SuperCollider 3.6.6\" to quit'".unixCmd;
		})
	);

	// start/stop machine Joure
	bMachineJoure = (Button(wGF, Rect(30, 420, 480, 30))
		.states_([
			["Start constructie geluidsobject Joure (05:06:874)", Color.white, Color(0.0, 0.0, 0.7, 0.7)],
			["Stop constructie geluidsobject Joure (05:06:874)", Color.white, Color(0.9, 0.0, 0.0, 0.9)]
		])
		.font_(cfg.fontReg)
		.action_({fButtonAction.value(bMachineJoure,fMachineJoure)}));

	// start/stop machine Makkum
	bMachineMakkum = (Button(wGF, Rect(30, 460, 480, 30))
		.states_([
			["Start constructie geluidsobject Makkum (04:23:035)", Color.white, Color(0.0, 0.0, 0.7, 0.7)],
			["Stop constructie geluidsobject Makkum (04:23:035)", Color.white, Color(0.9, 0.0, 0.0, 0.9)]
		])
		.font_(cfg.fontReg)
		.action_({fButtonAction.value(bMachineMakkum,fMachineMakkum)}));

	// start/stop machine Workum
	bMachineWorkum = (Button(wGF, Rect(30, 500, 480, 30))
		.states_([
			["Start constructie geluidsobject Workum (02:45:697)", Color.white, Color(0.0, 0.0, 0.7, 0.7)],
			["Stop constructie geluidsobject Workum (02:45:697)", Color.white, Color(0.9, 0.0, 0.0, 0.9)]
		])
		.font_(cfg.fontReg)
		.action_({fButtonAction.value(bMachineWorkum,fMachineWorkum)}));

	// start/stop machine Koudum
	bMachineKoudum = (Button(wGF, Rect(30, 540, 480, 30))
		.states_([
			["Start constructie geluidsobject Koudum (00:14:117)", Color.white, Color(0.0, 0.0, 0.7, 0.7)],
			["Stop constructie geluidsobject Koudum (00:14:117)", Color.white, Color(0.9, 0.0, 0.0, 0.9)]
		])
		.font_(cfg.fontReg)
		.action_({fButtonAction.value(bMachineKoudum,fMachineKoudum)}));

		// start/stop machine Grou
	bMachineGrou = (Button(wGF, Rect(30, 580, 480, 30))
		.states_([
			["Start constructie geluidsobject Grou (00:02:972)", Color.white, Color(0.0, 0.0, 0.7, 0.7)],
			["Stop constructie geluidsobject Grou (00:02:972)", Color.white, Color(0.9, 0.0, 0.0, 0.9)]
		])
		.font_(cfg.fontReg)
		.action_({fButtonAction.value(bMachineGrou,fMachineGrou)}));

	// record
	cRecord = (CheckBox.new(wGF, Rect(30,640,20,20))
		.background_(Color.white)
		.canFocus_(false));
	tRecord = (StaticText(wGF,Rect(50, 640, 200, 20))
		.stringColor_(Color.grey(0.1))
		.font_(cfg.fontSmall)
		.string_("Bewaar Resultaat"));

	// trigger enable
	tTrigger = (StaticText(wGF,Rect(330, 640, 150, 20))
		.stringColor_(Color.grey(0.1))
		.font_(cfg.fontSmall)
		.string_("Doel voor trigger"));
	pTrigger = (PopUpMenu.new(wGF, Rect(430,640,80,20))
		.stringColor_(Color.grey(0.1))
		.font_(cfg.fontSmall)
		.canFocus_(false)
		.items_(machineList)
		.action_({
			if(pTrigger.value != 0, {
				if(triggerSynth.isNil, {triggerSynth = Synth(\trigger, [\chan, cfg.bangChannel, \dbThresh, cfg.bangLevel])})
				}, {
					if(triggerSynth.notNil, {triggerSynth.free; triggerSynth = nil})
			});
		})
	);

	wGF2 = Window("Productie informatie", Rect(620, (screenHeight - 750), 550, 700));

	tProduction = (StaticText(wGF2, Rect(50,10,450,300))
		.stringColor_(Color.grey(0.3))
		.font_(cfg.fontBig)
		.string_("")
		.setProperty(\align, \center)
	);

	// time counter
	bCounter = (StaticText(wGF2, Rect(50,400,400,200))
		.stringColor_(Color.grey(0.3))
		.font_(cfg.fontHuge)
		.string_("")
		.setProperty(\align, \center)
	);

	w = Window("dummy").front; w.close;

	if(~wLiveSamplerAvail.isNil, {cfg.liveSamplerFile.loadRelative()});
	if(~wInOutAvail.isNil, {cfg.inOutFile.loadRelative()});

	(wGF
		.background_(Color.white)
		// .alpha_(0.9)
		.drawFunc = {
			// Pen.translate(100, 20);
			5.do{|i|
				Pen.color = Color.grey(rrand(0.6,0.9),rrand(0.8,1));
				Pen.lineDash = FloatArray[1,1];
				Pen.width = 3;
				Pen.addRect(
					Rect((wGF.bounds.width).rand, -2, 20, (wGF.bounds.height + 4))
				);
				Pen.perform(\stroke);
			}
	});

	(wGF2
		.background_(Color.white)
		// .alpha_(0.9)
		.drawFunc = {
			// Pen.translate(100, 20);
			5.do{|i|
				Pen.color = Color.grey(rrand(0.6,0.9),rrand(0.8,1));
				Pen.lineDash = FloatArray[1,1];
				Pen.width = 3;
				Pen.addRect(
					Rect((wGF2.bounds.width).rand, -2, 20, (wGF2.bounds.height + 4))
				);
				Pen.perform(\stroke);
			}
	});

	wGF.onClose_({
		cfg.localAddr.disconnect;
		task.stop;
		if(cfg.autoTrigger == 1, {tAutoTrigger.stop});
		OSCdef(\fabriekTrigger).free;
		cfg.localAddr.sendMsg("/midi/control", 15 - 1, 4, 0, "MUL");
		cfg.localAddr.sendMsg("/midi/control", 12 - 1, 0, 0, "MUL");
		if(triggerSynth.notNil, {triggerSynth.free});
		if(wGF2.isClosed, {}, {wGF2.close});
		~vol.free; if(~volWindow.notNil, {~volWindow.close});
	});

	wGF2.onClose_({
		if(wGF.isClosed, {}, {wGF.close});
	});

	// server volume controller
	~vol = s.volume; ~vol.gui;

	{
		wGF2.front;
		wGF.front;
	}.defer(1);

	// hide IDE
	// "osascript -e 'tell application \"System Events\" to set visible of process \"SuperCollider\" to false'".unixCmd;

	// set buttonlist here because buttons have to be created first
	buttonList = [bMachineJoure,bMachineMakkum,bMachineWorkum,bMachineKoudum,bMachineGrou];

	// set trigger to random
	// pTrigger.valueAction_(6);

	// start check task
	if(cfg.autoTrigger == 1, {tAutoTrigger.start});

	// set number of recording channels to 2
	s.recChannels_(2);
});
)


