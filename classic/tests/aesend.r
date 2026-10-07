/* aesend.r: the test tool's SIZE: it sends Apple events. */
#include "Processes.r"

resource 'SIZE' (-1) {
	reserved, acceptSuspendResumeEvents, reserved, canBackground, doesActivateOnFGSwitch,
	backgroundAndForeground, dontGetFrontClicks, ignoreChildDiedEvents, is32BitCompatible,
	isHighLevelEventAware, onlyLocalHLEvents, notStationeryAware, dontUseTextEditServices,
	reserved, reserved, reserved,
	256 * 1024, 256 * 1024
};
