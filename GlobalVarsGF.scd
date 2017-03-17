///////////////////////////////////////////// Global vars //////////////////////////////////////

// dependencies with MOTU:
//	if outResampling=1 then outResamplingChan should also be set as return channel in MOTU Audio Setup to resample the signal
//		from input 10/11
//	if outAnalogEfx=1 there should be busses in CueMix to send the analog efx input to outResamplingChan / outMainChan /
//		 outMonitorChan (when applicable)

// 	mapping 	outputs				inputs
//			0+1 = Main Out 1+2		0+1 = Analog In 1+2
//			2+3 = Analog Out 1+2	2+3 = Analog In 3+4
//			4+5 = Analog Out 3+4	4+5 = Analog In 5+6
//			6+7 = Analog Out 5+6	6+7 = Analog In 7+8
//			8+9 = Analog Out 7+8	8+9 = digital in
//								10+11 = return

if((~aBus.isNil || ~projectList.isNil), {

	~projectList = (sh: "Shackle", fr: "Free", gc: "Gedachtenconcert", ab: "ABATTOIR",
		tic: "TubesInChains", vv: "VanVan", sp: "Spoon3", mo: "MOROS",
		pa: "Parish", mw: "MoneyForYourWhale", md: "MDFreeze", frec: "FieldRecordings",
		sk: "SteenklankPresentatie", isp: "IstanPOOL");
	~project = ~projectList.sh; // set current project

	~aBus = ( // audio busses
		// ---- General (Main stereo out, Resampling from Analog 7-8, Input from Analog 1) ---------
		outMainChan: 0, // main output channel, stereo or mono
		outMainStereo: 1, // 0=mono 1=stereo
		outMainAtt: 0.8, // main attenuation factor: 1=no change
		outMonitor: 0, // 0=off 1=on
		outMonitorChan: 2, // monitor output channel, stereo or mono
		outMonitorStereo: 0, // 0=mono 1=stereo
		outMonitorAtt: 0.4, // monitor attenuation factor: 1=no change
		outAnalogEfx: 0, // 0=off 1=on
		outAnalogEfxChan: 6, // analog efx output channel, mono
		outAnalogEfxAtt: 0.1, // analog efx attenuation factor: 1=no change
		outResampling: 1, // 0=off 1=on
		outResamplingChan: 8, // output chan for resampling, stereo
		outResamplingAtt: 1, // resampling attenuation factor: 1=no change
		outAltChan: 4, // alternative output channel for incidental usage
		inChan1: 0, // input channel 1
		inChan2: 0, // input channel 2
		inChan1alt: 1, // alternative input channel for input 1
		inChan2alt: 1, // alternative input channel for input 2

		// ---- Tubes in Chains (Resampling from Analog 7-8 & No Analog Efx out & Input from Analog 1-2(3))---------
		//		outMainChan: 0, // main output channel, stereo or mono
		//		outMainStereo: 1, // 0=mono 1=stereo
		//		outMainAtt: 0.8, // main attenuation factor: 1=no change
		//		outMonitor: 0, // 0=off 1=on
		//		outMonitorChan: 2, // monitor output channel, stereo or mono
		//		outMonitorStereo: 0, // 0=mono 1=stereo
		//		outMonitorAtt: 0.8, // monitor attenuation factor: 1=no change
		//		outAnalogEfx: 0, // 0=off 1=on
		//		outAnalogEfxChan: 4, // analog efx output channel, mono
		//		outAnalogEfxAtt: 0.1, // analog efx attenuation factor: 1=no change
		//		outResampling: 1, // 0=off 1=on
		//		outResamplingChan: 8, // output chan for resampling, stereo
		//		inChan1: 0, // input channel 1 --- Anne
		//		inChan2: 2, // input channel 2 --- kistorgel
		//		inChan1alt: 0, // alternative input channel for input 1 --- Anne
		//		inChan2alt: 1, // alternative input channel for input 2 --- Sauer

		// ---- General vars for each project the same ---------
		inAlt: 0, // flag whether input is switched to alternative
		inChan1int: 10,  // output from computer send back in, left channel
		inChan2int: 11,  // output from computer send back in, right channel
		inInt: 0, // flag whether input is switched to internal
		outMainLimiter: 0, // 1=enable 0=disable
		outMainSubFilter: 1, // 1=enable 0=disable
		outAsynth: nil, outBsynth: nil, outBLsynth: nil, outMainSynth: nil, efx1Synth: nil, efx2Synth: nil,
		outA: 30, outB: 32, outMain: 34, outEfxPost: 36, outBL: 38, outEfxPre: 40,
		mainGroup: nil,
		outputGroup: nil,
		efxGroup: nil,
		synthGroup: nil
	);

	~aBus.put(\inChan1org, ~aBus.inChan1); // original input channel 1
	~aBus.put(\inChan2org, ~aBus.inChan2); // original input channel 2

	//	~colorOn = Color.yellow(0.9); // signal color ON
	~colorOn = Color.green(0.9);
	//	~colorOn = Color.new255(50,255,50); // signal color ON

	~lapisStatus = 0; 	// whether to start LapisStatus with LiveSampler
	~lapisStatusDestination = "local";
	// where to send OSC status updates from LS and SK / set to "local" or "touchOSC" or "both" or "none"

	~showBufferView = 0; // set to 1 to show bufferview window

	~oscSrc = "jx"; // set to "sc" to make the simulacrum work and if HID is fixed in 3.7

	~alwaysOnTop = 0; 	// Controller and In/Outputs windows on top or not
	~midiOutInit = 0; 	//  set to 1 to initialize MIDI out
	~midiOutDevice = "MUL";  // device to send MIDI out to if enables
});
