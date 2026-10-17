import Foundation

/// The live AI's tool definitions, and the mapping from its tool calls to app actions.
/// Keep this in step with AssistantAction. The list must not change between requests in a session,
/// because the model's reasoning is bound to the exact tool list it saw.
extension AssistantAction {
    static func fromTool(name: String, input: [String: Any]) -> AssistantAction? {
        func text(_ key: String) -> String {
            ((input[key] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func optional(_ key: String) -> String? {
            let value = text(key)
            return value.isEmpty ? nil : value
        }

        switch name {
        case "open_screen":
            switch text("screen") {
            case "camera": return .openScreen(.camera)
            case "web": return .openScreen(.web)
            case "tools": return .openScreen(.tools)
            case "history": return .openScreen(.history)
            case "messages": return .openScreen(.messages)
            case "reminders": return .openScreen(.reminders)
            case "briefing": return .openScreen(.briefing)
            case "safety": return .openScreen(.safety)
            case "caregiver": return .openScreen(.caregiver)
            case "settings": return .openScreen(.settings)
            case "accessibility_tips": return .openScreen(.accessibilityTips)
            default: return nil
            }
        case "take_photo":
            switch text("purpose") {
            case "read_text": return .readText
            case "scan_document": return .scanDocument
            case "identify_color": return .identifyColor
            case "find_object": return .findObject(text("target"))
            default: return .describeScene
            }
        case "open_website":
            return .openWebsite(text("name"))
        case "describe_web_page":
            return .describeWebPage
        case "read_web_page":
            return .readWebPage
        case "click_element":
            return .clickElement(text("target"))
        case "type_in_field":
            return .typeInField(target: text("target"), value: text("value"))
        case "scroll_page":
            return .scrollPage(down: text("direction") != "up")
        case "submit_form":
            return .submitForm
        case "set_reminder":
            return .setReminder(text("text"))
        case "call_contact":
            return .callContact(text("name"))
        case "send_email":
            return .composeEmail(to: optional("recipient"), message: optional("message"))
        case "send_text":
            return .composeText(to: optional("recipient"), message: optional("message"))
        case "read_messages":
            return .readMessages
        case "where_am_i":
            return .whereAmI
        case "emergency":
            return .emergency
        case "call_emergency_services":
            return .callEmergencyServices
        case "daily_briefing":
            return .dailyBriefing
        case "send_check_in":
            return .sendCheckIn
        case "switch_interface":
            return .switchInterface(text("mode") == "voice_only" ? .voiceOnly : .full)
        default:
            return nil
        }
    }

    static let toolDefinitions: [[String: Any]] = [
        tool("open_screen", "Open a screen in the app.", properties: [
            "screen": ["type": "string", "enum": ["camera", "web", "tools", "history", "messages", "reminders", "briefing", "safety", "caregiver", "settings", "accessibility_tips"]],
        ], required: ["screen"]),
        tool("take_photo", "Open the camera, take a photo and analyse it. Use when the user asks what is in front of them or around them, to read text or a label, to scan a document or letter, to identify a color, or to find an object. The app speaks the result to the user.", properties: [
            "purpose": ["type": "string", "enum": ["describe", "read_text", "scan_document", "identify_color", "find_object"]],
            "target": ["type": "string", "description": "What to find, for find_object. Empty otherwise."],
        ], required: ["purpose", "target"]),
        tool("open_website", "Open a website by name or address. Demo sites: news, pharmacy, appointment, bank.", properties: [
            "name": ["type": "string"],
        ], required: ["name"]),
        tool("describe_web_page", "Get a summary of the current web page and what the user can do on it.", properties: [:], required: []),
        tool("read_web_page", "Read the main text of the current web page aloud.", properties: [:], required: []),
        tool("click_element", "Press a button or link on the current web page, by its label or number.", properties: [
            "target": ["type": "string", "description": "The label or number of the element."],
        ], required: ["target"]),
        tool("type_in_field", "Type text into a form field on the current web page. Never used for passwords.", properties: [
            "target": ["type": "string", "description": "The field's label or number, or 'first'."],
            "value": ["type": "string"],
        ], required: ["target", "value"]),
        tool("scroll_page", "Scroll the current web page.", properties: [
            "direction": ["type": "string", "enum": ["up", "down"]],
        ], required: ["direction"]),
        tool("submit_form", "Submit the form on the current web page. The app shows the user what will be sent and asks them to approve.", properties: [:], required: []),
        tool("set_reminder", "Create a reminder. Include what and when in the text, for example 'take my pills at 8 pm every day'. The app asks for the time if it is missing.", properties: [
            "text": ["type": "string"],
        ], required: ["text"]),
        tool("call_contact", "Start a phone call to a contact by name. The app asks the user to approve first.", properties: [
            "name": ["type": "string"],
        ], required: ["name"]),
        tool("send_email", "Start writing an email with the user. The app asks for anything missing, reads the message back, and opens Mail for the user to tap Send.", properties: [
            "recipient": ["type": "string", "description": "Contact name if the user said one, else empty."],
            "message": ["type": "string", "description": "What the user wants to say, in their words, if they said it. Else empty."],
        ], required: ["recipient", "message"]),
        tool("send_text", "Start writing a text message with the user. The app asks for anything missing, reads the message back, and opens Messages for the user to tap Send.", properties: [
            "recipient": ["type": "string", "description": "Contact name if the user said one, else empty."],
            "message": ["type": "string", "description": "What the user wants to say, in their words, if they said it. Else empty."],
        ], required: ["recipient", "message"]),
        tool("read_messages", "Read the user's unread messages aloud one by one, letting them reply.", properties: [:], required: []),
        tool("where_am_i", "Tell the user where they are.", properties: [:], required: []),
        tool("emergency", "Start the emergency steps: call the emergency contact and text caregivers. The app asks the user to approve first.", properties: [:], required: []),
        tool("call_emergency_services", "Call the local emergency number, such as 112 or 911. Only when the user clearly asks for emergency services or says they are in danger. The app asks the user to approve first.", properties: [:], required: []),
        tool("daily_briefing", "Give the user a short briefing of the day: weather, reminders and unread messages.", properties: [:], required: []),
        tool("send_check_in", "Send the user's caregiver a short 'I am okay' check-in text. The app asks the user to approve first.", properties: [:], required: []),
        tool("switch_interface", "Switch between the full screen and voice-only mode.", properties: [
            "mode": ["type": "string", "enum": ["full", "voice_only"]],
        ], required: ["mode"]),
    ]

    private static func tool(_ name: String, _ description: String, properties: [String: Any], required: [String]) -> [String: Any] {
        [
            "name": name,
            "description": description,
            "strict": true,
            "input_schema": [
                "type": "object",
                "properties": properties,
                "required": required,
                "additionalProperties": false,
            ] as [String: Any],
        ]
    }
}
