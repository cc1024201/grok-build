use xai_grok_sampling_types::{
    ChatCompletionRequest, ReasoningEffort, parse_reasoning_effort_options,
};

#[test]
fn ultra_round_trips_as_client_profile() {
    let effort: ReasoningEffort = "ultra".parse().expect("ultra should parse");
    assert_eq!(effort, ReasoningEffort::Ultra);
    assert_eq!(effort.as_str(), "ultra");
    assert_eq!(serde_json::to_string(&effort).unwrap(), "\"ultra\"");
}

#[test]
fn ultra_maps_to_high_on_supported_provider_wires() {
    assert_eq!(
        ReasoningEffort::Ultra.to_responses_api(),
        xai_grok_sampling_types::rs::ReasoningEffort::High
    );
    assert_eq!(ReasoningEffort::Ultra.to_messages_api(), Some("high"));
}

#[test]
fn chat_completions_serializes_ultra_as_high() {
    let mut request = ChatCompletionRequest::new("grok-4.5", Vec::new());
    request.reasoning_effort = Some(ReasoningEffort::Ultra);
    let value = serde_json::to_value(request).expect("request should serialize");
    assert_eq!(value["reasoning_effort"], "high");
}

#[test]
fn provider_effort_metadata_remains_unmodified_by_client_ultra() {
    let values = [serde_json::json!("high"), serde_json::json!("low")];
    let options = xai_grok_sampling_types::parse_reasoning_effort_options(&values);
    assert_eq!(options.len(), 2);
    assert!(options.iter().all(|option| !option.value.is_ultra()));
}
