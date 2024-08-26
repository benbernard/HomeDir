/* *
 * This sample demonstrates handling intents from an Alexa skill using the Alexa Skills Kit SDK (v2).
 * Please visit https://alexa.design/cookbook for additional examples on implementing slots, dialog management,
 * session persistence, api calls, and more.
 * */
const Alexa = require("ask-sdk-core");

const LaunchRequestHandler = {
	canHandle(handlerInput) {
		return (
			Alexa.getRequestType(handlerInput.requestEnvelope) === "LaunchRequest"
		);
	},
	handle(handlerInput) {
		const speakOutput =
			"Welcome, you can say Hello or Help. Which would you like to try?";

		return handlerInput.responseBuilder
			.speak(speakOutput)
			.reprompt(speakOutput)
			.getResponse();
	},
};

const HelloWorldIntentHandler = {
	canHandle(handlerInput) {
		return (
			Alexa.getRequestType(handlerInput.requestEnvelope) === "IntentRequest" &&
			Alexa.getIntentName(handlerInput.requestEnvelope) === "HelloWorldIntent"
		);
	},
	handle(handlerInput) {
		const speakOutput = "Hello World!";

		return (
			handlerInput.responseBuilder
				.speak(speakOutput)
				//.reprompt('add a reprompt if you want to keep the session open for the user to respond')
				.getResponse()
		);
	},
};

const SeizureTrackerHandler = {
	canHandle(handlerInput) {
		return (
			Alexa.getRequestType(handlerInput.requestEnvelope) === "IntentRequest" &&
			Alexa.getIntentName(handlerInput.requestEnvelope) === "TrackSeizure"
		);
	},

	async handle(handlerInput) {
		const speakOutput = "Tracked";
		const value = Alexa.getSlotValue(
			handlerInput.requestEnvelope,
			"seizureDuration",
		);

		// Validate the seizure duration format
		const durationRegex = /^PT(\d+M)?(\d+S)?$/;
		if (!durationRegex.test(value)) {
			return handlerInput.responseBuilder
				.speak(
					"I didn't understand that duration. Please provide a duration in minutes and/or seconds, like '2 minutes 30 seconds' or '45 seconds'.",
				)
				.getResponse();
		}

		// Extract minutes and seconds from the duration
		const minutes = value.match(/(\d+)M/);
		const seconds = value.match(/(\d+)S/);
		let durationString = "";

		if (minutes) {
			durationString += `${minutes[1]} minute${minutes[1] === "1" ? "" : "s"}`;
		}
		if (minutes && seconds) {
			durationString += " and ";
		}
		if (seconds) {
			durationString += `${seconds[1]} second${seconds[1] === "1" ? "" : "s"}`;
		}

		// Convert duration to total seconds
		const totalSeconds =
			(minutes ? Number.parseInt(minutes[1]) * 60 : 0) +
			(seconds ? Number.parseInt(seconds[1]) : 0);

		const ky = await import("ky-universal").then((module) => module.default);

		const pacificTime = new Date().toLocaleString("en-US", {
			timeZone: "America/Los_Angeles",
		});

		try {
			await ky.post("https://hooks.zapier.com/hooks/catch/19913642/26cj2dl/", {
				json: {
					totalSeconds,
					date: pacificTime,
					notes: "",
				},
			});

			return handlerInput.responseBuilder
				.speak(`Tracked, ${durationString}`)
				.getResponse();
		} catch (error) {
			console.error("Error sending data to Zapier:", error);
			return handlerInput.responseBuilder
				.speak("Error sending data to Zapier")
				.getResponse();
		}
	},
};

const HelpIntentHandler = {
	canHandle(handlerInput) {
		return (
			Alexa.getRequestType(handlerInput.requestEnvelope) === "IntentRequest" &&
			Alexa.getIntentName(handlerInput.requestEnvelope) === "AMAZON.HelpIntent"
		);
	},
	handle(handlerInput) {
		const speakOutput = "You can say hello to me! How can I help?";

		return handlerInput.responseBuilder
			.speak(speakOutput)
			.reprompt(speakOutput)
			.getResponse();
	},
};

const CancelAndStopIntentHandler = {
	canHandle(handlerInput) {
		return (
			Alexa.getRequestType(handlerInput.requestEnvelope) === "IntentRequest" &&
			(Alexa.getIntentName(handlerInput.requestEnvelope) ===
				"AMAZON.CancelIntent" ||
				Alexa.getIntentName(handlerInput.requestEnvelope) ===
					"AMAZON.StopIntent")
		);
	},
	handle(handlerInput) {
		const speakOutput = "Goodbye!";

		return handlerInput.responseBuilder.speak(speakOutput).getResponse();
	},
};
/* *
 * FallbackIntent triggers when a customer says something that doesn’t map to any intents in your skill
 * It must also be defined in the language model (if the locale supports it)
 * This handler can be safely added but will be ingnored in locales that do not support it yet
 * */
const FallbackIntentHandler = {
	canHandle(handlerInput) {
		return (
			Alexa.getRequestType(handlerInput.requestEnvelope) === "IntentRequest" &&
			Alexa.getIntentName(handlerInput.requestEnvelope) ===
				"AMAZON.FallbackIntent"
		);
	},
	handle(handlerInput) {
		const speakOutput = "Sorry, I don't know about that. Please try again.";

		return handlerInput.responseBuilder
			.speak(speakOutput)
			.reprompt(speakOutput)
			.getResponse();
	},
};
/* *
 * SessionEndedRequest notifies that a session was ended. This handler will be triggered when a currently open
 * session is closed for one of the following reasons: 1) The user says "exit" or "quit". 2) The user does not
 * respond or says something that does not match an intent defined in your voice model. 3) An error occurs
 * */
const SessionEndedRequestHandler = {
	canHandle(handlerInput) {
		return (
			Alexa.getRequestType(handlerInput.requestEnvelope) ===
			"SessionEndedRequest"
		);
	},
	handle(handlerInput) {
		console.log(
			`~~~~ Session ended: ${JSON.stringify(handlerInput.requestEnvelope)}`,
		);
		// Any cleanup logic goes here.
		return handlerInput.responseBuilder.getResponse(); // notice we send an empty response
	},
};
/* *
 * The intent reflector is used for interaction model testing and debugging.
 * It will simply repeat the intent the user said. You can create custom handlers for your intents
 * by defining them above, then also adding them to the request handler chain below
 * */
const IntentReflectorHandler = {
	canHandle(handlerInput) {
		return (
			Alexa.getRequestType(handlerInput.requestEnvelope) === "IntentRequest"
		);
	},
	handle(handlerInput) {
		const intentName = Alexa.getIntentName(handlerInput.requestEnvelope);
		const speakOutput = `You just triggered ${intentName}`;

		return (
			handlerInput.responseBuilder
				.speak(speakOutput)
				//.reprompt('add a reprompt if you want to keep the session open for the user to respond')
				.getResponse()
		);
	},
};
/**
 * Generic error handling to capture any syntax or routing errors. If you receive an error
 * stating the request handler chain is not found, you have not implemented a handler for
 * the intent being invoked or included it in the skill builder below
 * */
const ErrorHandler = {
	canHandle() {
		return true;
	},
	handle(handlerInput, error) {
		const speakOutput =
			"Sorry, I had trouble doing what you asked. Please try again.";
		console.log(`~~~~ Error handled: ${JSON.stringify(error)}`);

		return handlerInput.responseBuilder
			.speak(speakOutput)
			.reprompt(speakOutput)
			.getResponse();
	},
};

/**
 * This handler acts as the entry point for your skill, routing all request and response
 * payloads to the handlers above. Make sure any new handlers or interceptors you've
 * defined are included below. The order matters - they're processed top to bottom
 * */
exports.handler = Alexa.SkillBuilders.custom()
	.addRequestHandlers(
		LaunchRequestHandler,
		HelloWorldIntentHandler,
		SeizureTrackerHandler,
		HelpIntentHandler,
		CancelAndStopIntentHandler,
		FallbackIntentHandler,
		SessionEndedRequestHandler,
		IntentReflectorHandler,
	)
	.addErrorHandlers(ErrorHandler)
	.withCustomUserAgent("sample/hello-world/v1.2")
	.lambda();
